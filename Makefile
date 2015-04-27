CODE_DIR = src

.PHONY: project

project:
	       $(MAKE) -C $(CODE_DIR)
clean:
	       $(MAKE) -C $(CODE_DIR) clean
