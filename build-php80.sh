#!/bin/bash
#
# FrankenPHP PHP 8.0 Build Script
# This script builds FrankenPHP with PHP 8.0 ZTS from source on macOS/Linux
#
# Usage:
#   ./build-php80.sh [options]
#
# Options:
#   --php-version VERSION    PHP version to build (default: 8.0.30)
#   --build-dir DIR          Build directory (default: ~/php-build)
#   --install-dir DIR        PHP install directory (default: ~/php-8.0-zts-embed)
#   --skip-php-build         Skip PHP build if already exists
#   --clean                   Clean build directories before building
#   --help                    Show this help message
#

set -o errexit
set -o pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
PHP_VERSION="${PHP_VERSION:-8.0.30}"
BUILD_DIR="${BUILD_DIR:-$HOME/php-build}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/php-8.0-zts-embed}"
SKIP_PHP_BUILD="${SKIP_PHP_BUILD:-0}"
CLEAN="${CLEAN:-0}"

# Detect platform
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
NPROC=$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)

# FrankenPHP source directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_help() {
    head -20 "$0" | tail -15
    exit 0
}

check_dependencies() {
    log_info "Checking dependencies..."

    local missing_deps=()

    # Check for required tools
    for cmd in wget tar make gcc go; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        if [ "$OS" = "darwin" ]; then
            log_info "Install with: brew install ${missing_deps[*]}"
        else
            log_info "Install with your package manager (apt, yum, etc.)"
        fi
        exit 1
    fi

    # Check Go version
    GO_VERSION=$(go version | grep -oE '[0-9]+\.[0-9]+' | head -1)
    log_info "Go version: $GO_VERSION"

    log_success "All dependencies satisfied"
}

install_macos_deps() {
    if [ "$OS" != "darwin" ]; then
        return
    fi

    log_info "Installing macOS dependencies via Homebrew..."

    # Required packages
    local packages="libiconv bison re2c pkg-config brotli openssl@1.1"

    for pkg in $packages; do
        if ! brew list "$pkg" &>/dev/null; then
            log_info "Installing $pkg..."
            brew install "$pkg"
        fi
    done

    # Add bison to PATH for this session
    export PATH="/opt/homebrew/opt/bison/bin:$PATH"

    log_success "macOS dependencies installed"
}

install_linux_deps() {
    if [ "$OS" != "linux" ]; then
        return
    fi

    log_info "Please ensure you have the following packages installed:"
    log_info "  - build-essential (gcc, make)"
    log_info "  - libxml2-dev"
    log_info "  - libsqlite3-dev"
    log_info "  - libssl-dev"
    log_info "  - libbrotli-dev"
    log_info "  - pkg-config"
    log_info "  - bison"
    log_info "  - re2c"
    log_info ""
    log_info "Ubuntu/Debian: sudo apt install build-essential libxml2-dev libsqlite3-dev libssl-dev libbrotli-dev pkg-config bison re2c"
    log_info "RHEL/CentOS: sudo yum install gcc make libxml2-devel sqlite-devel openssl-devel brotli-devel pkgconfig bison re2c"
}

download_php() {
    local php_tarball="php-${PHP_VERSION}.tar.gz"
    local php_url="https://www.php.net/distributions/${php_tarball}"

    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"

    if [ -f "$php_tarball" ] && [ "$CLEAN" != "1" ]; then
        log_info "PHP source already downloaded, skipping..."
        return
    fi

    log_info "Downloading PHP ${PHP_VERSION}..."
    wget -O "$php_tarball" "$php_url"

    log_success "PHP source downloaded"
}

extract_php() {
    cd "$BUILD_DIR"

    local php_dir="php-${PHP_VERSION}"

    if [ -d "$php_dir" ] && [ "$CLEAN" = "1" ]; then
        log_info "Cleaning existing PHP source directory..."
        rm -rf "$php_dir"
    fi

    if [ -d "$php_dir" ]; then
        log_info "PHP source already extracted, skipping..."
        return
    fi

    log_info "Extracting PHP source..."
    tar xf "php-${PHP_VERSION}.tar.gz"

    log_success "PHP source extracted"
}

configure_php() {
    cd "$BUILD_DIR/php-${PHP_VERSION}"

    if [ -f "Makefile" ] && [ "$CLEAN" != "1" ]; then
        log_info "PHP already configured, skipping..."
        return
    fi

    log_info "Configuring PHP ${PHP_VERSION} with ZTS and embed SAPI..."

    # Add bison to PATH on macOS
    if [ "$OS" = "darwin" ]; then
        export PATH="/opt/homebrew/opt/bison/bin:$PATH"
    fi

    local configure_opts=(
        "--enable-embed=static"
        "--enable-zts"
        "--disable-zend-signals"
        "--disable-opcache-jit"
        "--enable-static"
        "--enable-shared=no"
        "--prefix=${INSTALL_DIR}"
    )

    # Platform-specific options
    if [ "$OS" = "darwin" ]; then
        configure_opts+=("--with-iconv=/opt/homebrew/opt/libiconv/")
    fi

    ./configure "${configure_opts[@]}"

    log_success "PHP configured"
}

build_php() {
    cd "$BUILD_DIR/php-${PHP_VERSION}"

    if [ -f "libs/libphp.a" ] && [ "$CLEAN" != "1" ]; then
        log_info "PHP already built, skipping..."
        return
    fi

    log_info "Building PHP ${PHP_VERSION} (using $NPROC cores)..."
    make -j"$NPROC"

    log_success "PHP built successfully"
}

verify_php() {
    cd "$BUILD_DIR/php-${PHP_VERSION}"

    log_info "Verifying PHP build..."

    # Check for required files
    if [ ! -f "libs/libphp.a" ]; then
        log_error "libphp.a not found!"
        exit 1
    fi

    if [ ! -f "sapi/cli/php" ]; then
        log_error "PHP CLI not found!"
        exit 1
    fi

    # Verify ZTS
    local php_version_output
    php_version_output=$(./sapi/cli/php -v 2>&1 || true)

    if echo "$php_version_output" | grep -q "ZTS"; then
        log_success "PHP ${PHP_VERSION} ZTS verified"
    else
        log_error "PHP is not built with ZTS!"
        echo "$php_version_output"
        exit 1
    fi

    # Show version
    log_info "PHP version:"
    ./sapi/cli/php -v
}

build_frankenphp() {
    cd "$SCRIPT_DIR/caddy/frankenphp"

    log_info "Building FrankenPHP with PHP ${PHP_VERSION}..."

    local php_build="$BUILD_DIR/php-${PHP_VERSION}"

    # Set CGO flags
    local cgo_cflags="-I${php_build}/include -I${php_build}/main -I${php_build} -I${php_build}/TSRM -I${php_build}/Zend -I${php_build}/sapi/embed"
    local cgo_ldflags="-L${php_build}/libs -lphp"

    # Platform-specific flags
    if [ "$OS" = "darwin" ]; then
        cgo_cflags="${cgo_cflags} -I/opt/homebrew/include"
        cgo_ldflags="${cgo_ldflags} -L/opt/homebrew/opt/libiconv/lib -liconv -lresolv -lm -lpthread -lxml2 -lsqlite3 -lssl -lcrypto -L/opt/homebrew/lib -lbrotlienc -lbrotlidec -lbrotlicommon"
    else
        cgo_ldflags="${cgo_ldflags} -lresolv -lm -lpthread -lxml2 -lsqlite3 -lssl -lcrypto -lbrotlienc -lbrotlidec -lbrotlicommon"
    fi

    # Build tags
    local build_tags="nobadger,nomysql,nopgx,nowatcher"

    log_info "CGO_CFLAGS: $cgo_cflags"
    log_info "CGO_LDFLAGS: $cgo_ldflags"
    log_info "Build tags: $build_tags"

    CGO_CFLAGS="$cgo_cflags" \
    CGO_LDFLAGS="$cgo_ldflags" \
    go build -tags="$build_tags"

    log_success "FrankenPHP built successfully"
}

verify_frankenphp() {
    cd "$SCRIPT_DIR/caddy/frankenphp"

    log_info "Verifying FrankenPHP build..."

    if [ ! -f "frankenphp" ]; then
        log_error "FrankenPHP binary not found!"
        exit 1
    fi

    # Show version
    log_info "FrankenPHP version:"
    ./frankenphp version

    # Show PHP version
    log_info "Embedded PHP version:"
    ./frankenphp php-cli -r 'echo "PHP " . PHP_VERSION . " (" . (PHP_ZTS ? "ZTS" : "NTS") . ")\n";'

    # Quick test
    log_info "Running quick test..."
    local test_output
    test_output=$(./frankenphp php-cli -r 'echo "FrankenPHP OK";' 2>&1)

    if [ "$test_output" = "FrankenPHP OK" ]; then
        log_success "FrankenPHP is working correctly!"
    else
        log_error "FrankenPHP test failed!"
        echo "$test_output"
        exit 1
    fi
}

show_summary() {
    echo ""
    echo "=============================================="
    echo "           Build Summary"
    echo "=============================================="
    echo ""
    echo "PHP Version:        ${PHP_VERSION}"
    echo "PHP Build Dir:      ${BUILD_DIR}/php-${PHP_VERSION}"
    echo "Platform:           ${OS} (${ARCH})"
    echo ""
    echo "FrankenPHP Binary:  ${SCRIPT_DIR}/caddy/frankenphp/frankenphp"
    echo ""
    echo "Usage:"
    echo "  # Run PHP script"
    echo "  ./caddy/frankenphp/frankenphp php-cli /path/to/script.php"
    echo ""
    echo "  # Start server"
    echo "  ./caddy/frankenphp/frankenphp run"
    echo ""
    log_success "Build completed successfully!"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --php-version)
            PHP_VERSION="$2"
            shift 2
            ;;
        --build-dir)
            BUILD_DIR="$2"
            shift 2
            ;;
        --install-dir)
            INSTALL_DIR="$2"
            shift 2
            ;;
        --skip-php-build)
            SKIP_PHP_BUILD=1
            shift
            ;;
        --clean)
            CLEAN=1
            shift
            ;;
        --help|-h)
            show_help
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            ;;
    esac
done

# Main execution
main() {
    echo ""
    echo "=============================================="
    echo "  FrankenPHP PHP 8.0 Build Script"
    echo "=============================================="
    echo ""
    echo "Configuration:"
    echo "  PHP Version:   ${PHP_VERSION}"
    echo "  Build Dir:     ${BUILD_DIR}"
    echo "  Install Dir:   ${INSTALL_DIR}"
    echo "  Platform:      ${OS} (${ARCH})"
    echo "  CPU Cores:     ${NPROC}"
    echo ""

    check_dependencies

    if [ "$OS" = "darwin" ]; then
        install_macos_deps
    else
        install_linux_deps
    fi

    if [ "$SKIP_PHP_BUILD" != "1" ]; then
        download_php
        extract_php
        configure_php
        build_php
        verify_php
    else
        log_info "Skipping PHP build (--skip-php-build)"
    fi

    build_frankenphp
    verify_frankenphp
    show_summary
}

main "$@"
