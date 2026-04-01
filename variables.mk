APPLICATION := $(shell basename `pwd`)
BRANCH := $(shell git rev-parse --abbrev-ref HEAD)
BUILD_RFC3339 := $(shell date -u +"%Y-%m-%dT%H:%M:%S+00:00")
PACKAGE := $(shell git remote get-url --push origin | sed -E 's/.+[@|/].+[/|:](.+)\/(.+).git/\1\/\2/')
REVISION := $(shell git rev-parse HEAD)
VERSION := $(shell git describe --tags)
DESCRIPTION = $(shell curl -s https://api.github.com/repos/${PACKAGE} \
    | grep '"description".*' \
    | head -n 1 \
    | cut -d '"' -f 4)
WORKDIR := $(shell pwd)

DOCKER_BUILD_ARGS = \
	--build-arg APPLICATION=${APPLICATION} \
	--build-arg BUILD_RFC3339=${BUILD_RFC3339} \
	--build-arg DESCRIPTION="${DESCRIPTION}" \
	--build-arg PACKAGE=${PACKAGE} \
	--build-arg REVISION=${REVISION} \
	--build-arg VERSION=${VERSION} \
	--progress auto

.PHONY: debug-variables docker update-hooks

.PHONY: debug-variables
debug-variables:
	@echo "APPLICATION: ${APPLICATION}"
	@echo "BRANCH: ${BRANCH}"
	@echo "BUILD_RFC3339: ${BUILD_RFC3339}"
	@echo "DESCRIPTION: ${DESCRIPTION}"
	@echo "PACKAGE: ${PACKAGE}"
	@echo "REVISION: ${REVISION}"
	@echo "VERSION: ${VERSION}"
	@echo "WORKDIR: ${WORKDIR}"

# docker removes and rebuilds the docker container for local development
docker:
	docker rmi ${APPLICATION}:${BRANCH} || true
	docker build ${DOCKER_BUILD_ARGS} -f build/package/Dockerfile -t ${APPLICATION}:${BRANCH} .
