# Delegates all targets to the stocktrader-operator subdirectory.
# Run any make target from the repo root as usual, e.g.:
#   make docker-build IMG=<registry>/<name>:<tag>
#   make deploy IMG=<registry>/<name>:<tag>
%:
	$(MAKE) -C stocktrader-operator $@
