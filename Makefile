.PHONY: build test test-fuzz test-invariant anvil deploy deploy-anvil deploy-sepolia

-include .env
export

SCRIPT := script/DeployUniswapSPD.s.sol:DeployUniswapSPD
TEST_MODE ?= 1
FUZZ_RUNS ?= 5
INVARIANT_RUNS ?= 32
INVARIANT_DEPTH ?= 32
RPC := $(if $(filter 1,$(TEST_MODE)),$(RPC_URL_ANVIL),$(RPC_URL))

build:
	forge build

test:
	forge test $(ARGS)

test-fuzz:
	forge test --match-path 'test/fuzz/*.t.sol' --fuzz-runs $(FUZZ_RUNS) $(ARGS)

test-invariant:
	FOUNDRY_INVARIANT_RUNS=$(INVARIANT_RUNS) FOUNDRY_INVARIANT_DEPTH=$(INVARIANT_DEPTH) \
		forge test --match-path 'test/invariant/*.t.sol' $(ARGS)

anvil:
	anvil $(ARGS)

deploy:
	TEST_MODE=$(TEST_MODE) forge script $(SCRIPT) --rpc-url "$(RPC)" --broadcast $(ARGS)

deploy-anvil:
	$(MAKE) deploy TEST_MODE=1

deploy-sepolia:
	$(MAKE) deploy TEST_MODE=0
