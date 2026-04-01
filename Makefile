include variables.mk

.PHONY: build all
.DEFAULT_GOAL := all

all: build

build:
	docker build ${DOCKER_BUILD_ARGS} -f build/package/Dockerfile -t ${APPLICATION}:${BRANCH} .

exec:
	docker run -it --rm --entrypoint=/bin/sh ${APPLICATION}:${BRANCH}

docker-nuke:
	docker compose -f test/docker-compose.test.yml down --rmi all --remove-orphans -v

docker-clean:
	docker compose -f test/docker-compose.test.yml down --remove-orphans -v

docker-down:
	docker compose -f test/docker-compose.test.yml down

docker-up:
	docker compose -f test/docker-compose.test.yml up

docker-test: docker-nuke
	docker compose -f test/docker-compose.test.yml up --exit-code-from sut
