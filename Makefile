.DEFAULT_GOAL := help
.PHONY: help build test check-l10n run install icon dist release clean

help: ## 사용 가능한 명령 보기
	@grep -E '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  make %-10s %s\n", $$1, $$2}'

build: ## 디버그 빌드 (코드 확인용)
	swift build

test: ## 테스트 실행
	swift test

check-l10n: ## 번역 누락 확인
	Scripts/check-localization.sh

run: ## .app으로 만들어서 바로 실행 (설치하지 않음)
	Scripts/bundle.sh
	open build/ClipboardManager.app

install: ## ~/Applications에 설치하고 실행 (평소 사용)
	Scripts/bundle.sh --install

icon: ## 앱 아이콘 다시 생성
	swift Scripts/make-icon.swift Resources/AppIcon.iconset

dist: ## 배포 파일 생성: universal zip, dmg, SHA256SUMS (build/)
	Scripts/bundle.sh --universal --dist

release: ## 새 버전 릴리즈: make release VERSION=1.2.3
	Scripts/release.sh $(VERSION)

clean: ## 빌드 산출물 삭제
	rm -rf .build build
