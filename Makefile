# =========================
# Minimal Makefile (helm template + kubectl apply/delete + hooks)
# =========================

SHELL := /usr/bin/env bash
.SHELLFLAGS := -euo pipefail -c

# ---- Tools ----
HELM    ?= helm
KUBECTL ?= kubectl

# ---- Chart / Namespace / Scenarios ----
RELEASE     ?= training
NAMESPACE   ?= up0134-training
CHART       ?= ./charts/case-scenario
VALUES_DIR  ?= ./scenarios
RENDER_DIR  ?= /tmp/training
OUT_FILE    ?= $(RENDER_DIR)/$(SCENARIO).yaml

# ---- Scenario (支援簡寫 S=) ----
SCENARIO ?=
ifeq ($(strip $(SCENARIO)),)
  ifneq ($(strip $(S)),)
    SCENARIO := $(S)
  endif
endif

VALUES_FILE   := $(VALUES_DIR)/$(SCENARIO).yaml
SCENARIO_LIST := $(basename $(notdir $(wildcard $(VALUES_DIR)/*.yaml)))

# ---- Pretty printer (has bat? else cat) ----
CAT := $(shell command -v bat >/dev/null 2>&1 && echo "bat --style=plain" || echo "cat")

# ---- Safety guards ----
FORBIDDEN_NS = ^(default|kube-system|kube-public|kube-node-lease|openshift.*|kube-.*)$$

define guard_namespace
	@if echo "$(NAMESPACE)" | grep -Eiq "$(FORBIDDEN_NS)"; then \
		echo "Refuse to operate on forbidden namespace: $(NAMESPACE)"; \
		exit 1; \
	fi
endef

define guard_scenario
	@if [ -z "$(SCENARIO)" ]; then \
		echo "Please set scenario, e.g."; \
		echo "  make template S=<name>"; \
		echo "  make apply    S=<name>"; \
		echo "  make delete   S=<name>"; \
		echo "Available:"; for s in $(SCENARIO_LIST); do echo "  - $$s"; done; \
		exit 1; \
	fi; \
	if [ ! -f "$(VALUES_FILE)" ]; then \
		echo "Values file not found: $(VALUES_FILE)"; \
		exit 1; \
	fi
endef

# ---- Hooks ----
HOOK_DIR     ?= ./scenarios/hooks
ENABLE_HOOKS ?= 1

# ---- Targets ----
.PHONY: help
help:
	@echo "Targets:"
	@echo "  make scenarios                 # List scenarios ($(VALUES_DIR)/*.yaml)"
	@echo "  make template S=<name>         # Render manifests to $(RENDER_DIR)"
	@echo "  make apply    S=<name>         # kubectl apply -f rendered manifests (with hooks)"
	@echo "  make delete   S=<name>         # kubectl delete -f rendered manifests (with hooks)"
	@echo "  make status                    # kubectl get overview in $(NAMESPACE)"
	@echo "  make current                   # Show recorded current scenario (ConfigMap)"

.PHONY: scenarios
scenarios:
	@ls -1 $(VALUES_DIR)/*.yaml 2>/dev/null | sed 's|.*/||; s|\.yaml$$||' || echo "(none)"

.PHONY: _run_hook
_run_hook:
	@phase="$(PHASE)"; \
	hook="$(HOOK_DIR)/$(SCENARIO).$$phase.sh"; \
	if [ "$(ENABLE_HOOKS)" = "1" ] && [ -f "$$hook" ]; then \
		echo "==> Running hook: $$hook"; \
		SCENARIO="$(SCENARIO)" \
		NAMESPACE="$(NAMESPACE)" \
		VALUES_FILE="$(VALUES_FILE)" \
		OUT_FILE="$(OUT_FILE)" \
		RENDER_DIR="$(RENDER_DIR)" \
		/usr/bin/bash "$$hook" "$(SCENARIO)" "$(NAMESPACE)" "$(OUT_FILE)"; \
	else \
		echo "(no $$phase hook $$hook for $(SCENARIO))"; \
	fi

.PHONY: template
template:
	$(guard_scenario)
	@mkdir -p "$(RENDER_DIR)"
	@echo "==> Rendering to: $(OUT_FILE)"
	@$(HELM) template "$(RELEASE)" "$(CHART)" \
		-n "$(NAMESPACE)" \
		-f "$(VALUES_FILE)" \
		--set global.scenario="$(SCENARIO)" \
		--set namespace.name="$(NAMESPACE)" \
		> "$(OUT_FILE)"
	@$(CAT) "$(OUT_FILE)"

.PHONY: apply
apply:
	$(guard_namespace)
	$(guard_scenario)
	@$(MAKE) template S="$(SCENARIO)"
	@$(MAKE) _run_hook PHASE=pre S="$(SCENARIO)"
	@echo "==> Applying: $(OUT_FILE)"
	@$(KUBECTL) apply -f "$(OUT_FILE)"
	@$(KUBECTL) -n "$(NAMESPACE)" create configmap training-state \
		--from-literal=scenario="$(SCENARIO)" \
		--dry-run=client -o yaml | $(KUBECTL) apply -f -
	@$(MAKE) _run_hook PHASE=post S="$(SCENARIO)"
	@echo "Applied scenario: $(SCENARIO) to $(NAMESPACE)"

.PHONY: delete
delete:
	$(guard_namespace)
	$(guard_scenario)
	@if [ ! -s "$(OUT_FILE)" ]; then \
		echo "Rendered file missing, re-rendering $(OUT_FILE) for precise delete..."; \
		$(MAKE) template S="$(SCENARIO)"; \
	fi
	@$(MAKE) _run_hook PHASE=pre-delete S="$(SCENARIO)"
	@echo "==> Deleting by file: $(OUT_FILE)"
	@$(KUBECTL) delete -f "$(OUT_FILE)" --ignore-not-found
	@$(KUBECTL) -n "$(NAMESPACE)" delete configmap training-state --ignore-not-found
	@$(MAKE) _run_hook PHASE=post-delete S="$(SCENARIO)"
	@echo "Deleted scenario: $(SCENARIO) from $(NAMESPACE)"

.PHONY: status
status:
	@echo "==> Resources in namespace: $(NAMESPACE)"
	@$(KUBECTL) -n "$(NAMESPACE)" get ns 2>/dev/null | grep -E "NAME|$(NAMESPACE)" || true
	@$(KUBECTL) -n "$(NAMESPACE)" get all 2>/dev/null || true
	@$(KUBECTL) -n "$(NAMESPACE)" get route 2>/dev/null || true
	@$(KUBECTL) -n "$(NAMESPACE)" get ingresses.networking.k8s.io 2>/dev/null || true

.PHONY: current
current:
	@$(KUBECTL) -n "$(NAMESPACE)" get cm training-state -o jsonpath='{.data.scenario}' 2>/dev/null || echo "(none)"
