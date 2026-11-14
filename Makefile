.PHONY: build run

build:
	cmake -S . -B build/product-webkit -G Xcode -DJENA_ENGINE=WEBKIT
	cmake --build build/product-webkit --config Debug --target JenaWeb

run: build
	open -n build/product-webkit/Debug/JenaWeb.app
