.PHONY: build run exec push dev all

all: build run

dev: build exec

build:
	docker rmi jnovack/ambassador || true
	docker build -t jnovack/ambassador .

run:
	docker run -it --rm jnovack/ambassador

exec:
	docker run -it --rm --entrypoint=/bin/sh jnovack/ambassador

push: build
	docker push jnovack/ambassador