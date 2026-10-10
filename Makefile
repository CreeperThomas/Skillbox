SHELL := /bin/bash
.PHONY: test build app run icon

test:
	bash scripts/swift-env.sh swift test --disable-sandbox --disable-xctest --enable-swift-testing
	bash scripts/swift-env.sh swift run --disable-sandbox SkillboxChecks

build:
	bash scripts/swift-env.sh swift build --disable-sandbox -c release

icon:
	bash scripts/make-icon.sh

app: build
	bash scripts/make-app.sh

run:
	bash scripts/swift-env.sh swift run --disable-sandbox Skillbox
