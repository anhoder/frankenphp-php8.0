# Building FrankenPHP with PHP 8.0

This document describes how to build FrankenPHP with PHP 8.0 support from source. PHP 8.0 requires building PHP from source with specific configuration options since most package managers don't provide PHP 8.0 with both ZTS (Zend Thread Safety) and embed SAPI enabled.

> **Note**: When using PHP 8.0, Zend Max Execution Timers are not available, so timeouts (e.g., `max_execution_time`) will be automatically disabled. PHP 8.1+ is recommended for full functionality.

## Quick Start (Automated)

Use the provided build script for a fully automated build:

```bash
# Default build (PHP 8.0.30)
./build-php80.sh

# Custom PHP version
./build-php80.sh --php-version 8.0.28

# Clean build
./build-php80.sh --clean

# Skip PHP build (if already built)
./build-php80.sh --skip-php-build
```

## Manual Build Process

### Prerequisites

#### macOS

Install required dependencies via Homebrew:

```bash
brew install libiconv bison re2c pkg-config brotli openssl@1.1 go

# Add bison to PATH
echo 'export PATH="/opt/homebrew/opt/bison/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

#### Linux (Ubuntu/Debian)

```bash
sudo apt update
sudo apt install -y \
    build-essential \
    libxml2-dev \
    libsqlite3-dev \
    libssl-dev \
    libbrotli-dev \
    pkg-config \
    bison \
    re2c \
    golang
```

#### Linux (RHEL/CentOS)

```bash
sudo yum install -y \
    gcc \
    make \
    libxml2-devel \
    sqlite-devel \
    openssl-devel \
    brotli-devel \
    pkgconfig \
    bison \
    re2c \
    golang
```

### Step 1: Download and Extract PHP Source

```bash
# Create build directory
mkdir -p ~/php-build && cd ~/php-build

# Download PHP 8.0.30
wget https://www.php.net/distributions/php-8.0.30.tar.gz

# Extract
tar xf php-8.0.30.tar.gz
cd php-8.0.30
```

### Step 2: Configure PHP

#### macOS Configuration

```bash
export PATH="/opt/homebrew/opt/bison/bin:$PATH"

./configure \
    --enable-embed=static \
    --enable-zts \
    --disable-zend-signals \
    --disable-opcache-jit \
    --enable-static \
    --enable-shared=no \
    --with-iconv=/opt/homebrew/opt/libiconv/
```

#### Linux Configuration

```bash
./configure \
    --enable-embed=static \
    --enable-zts \
    --disable-zend-signals \
    --disable-opcache-jit \
    --enable-static \
    --enable-shared=no
```

### Step 3: Build PHP

```bash
# Build using all available CPU cores
make -j$(nproc)

# Verify the build
./sapi/cli/php -v
# Should show: PHP 8.0.30 (cli) (...) ( ZTS )
```

### Step 4: Verify PHP Build

Check that required files exist:

```bash
# Static library (required)
ls -la libs/libphp.a

# PHP CLI binary
ls -la sapi/cli/php

# Embed SAPI header
ls -la sapi/embed/php_embed.h
```

### Step 5: Build FrankenPHP

Navigate to FrankenPHP source and build:

```bash
cd /path/to/frankenphp/caddy/frankenphp

# Set PHP build path
export PHP_BUILD=~/php-build/php-8.0.30
```

#### macOS Build

```bash
CGO_CFLAGS="-I${PHP_BUILD}/include -I${PHP_BUILD}/main -I${PHP_BUILD} -I${PHP_BUILD}/TSRM -I${PHP_BUILD}/Zend -I${PHP_BUILD}/sapi/embed -I/opt/homebrew/include" \
CGO_LDFLAGS="-L${PHP_BUILD}/libs -lphp -L/opt/homebrew/opt/libiconv/lib -liconv -lresolv -lm -lpthread -lxml2 -lsqlite3 -lssl -lcrypto -L/opt/homebrew/lib -lbrotlienc -lbrotlidec -lbrotlicommon" \
go build -tags=nobadger,nomysql,nopgx,nowatcher
```

#### Linux Build

```bash
CGO_CFLAGS="-I${PHP_BUILD}/include -I${PHP_BUILD}/main -I${PHP_BUILD} -I${PHP_BUILD}/TSRM -I${PHP_BUILD}/Zend -I${PHP_BUILD}/sapi/embed" \
CGO_LDFLAGS="-L${PHP_BUILD}/libs -lphp -lresolv -lm -lpthread -lxml2 -lsqlite3 -lssl -lcrypto -lbrotlienc -lbrotlidec -lbrotlicommon" \
go build -tags=nobadger,nomysql,nopgx,nowatcher
```

### Step 6: Verify FrankenPHP Build

```bash
# Check version
./frankenphp version

# Check embedded PHP version
./frankenphp php-cli -r 'echo PHP_VERSION . " " . (PHP_ZTS ? "ZTS" : "NTS") . "\n";'
# Expected output: 8.0.30 ZTS

# Run a test script
echo '<?php echo "Hello from FrankenPHP with PHP 8.0!";' > /tmp/test.php
./frankenphp php-cli /tmp/test.php
```

## Build Tags Reference

| Tag | Description |
|-----|-------------|
| `nobadger` | Disable BadgerDB storage |
| `nomysql` | Disable MySQL storage |
| `nopgx` | Disable PostgreSQL storage |
| `nowatcher` | Disable file watcher (hot reload) |
| `nobrotli` | Disable Brotli compression |

## Troubleshooting

### Error: `php_embed.h` not found

This error occurs when PHP is not built with the embed SAPI. Ensure you configured PHP with `--enable-embed=static`.

### Error: `ZEND_STR_AUTOGLOBAL_ENV` undeclared

This error occurs when building with an unmodified FrankenPHP against PHP 8.0. The FrankenPHP source needs PHP 8.0 compatibility patches. See the C code modifications section below.

### Error: `arPacked` member not found

The `arPacked` field in `HashTable` was introduced in PHP 8.1. PHP 8.0 uses `arData` for packed arrays. The FrankenPHP source needs to be patched for PHP 8.0 compatibility.

### Linker warnings about duplicate libraries

These warnings are harmless and can be ignored:
```
ld: warning: ignoring duplicate libraries: '-lxml2', '-lssl', ...
```

## PHP 8.0 Compatibility Patches

FrankenPHP requires the following C code modifications to support PHP 8.0:

### 1. `frankenphp.c` - Add compatibility macros

Add after includes:

```c
/* PHP 8.0 compatibility macros */
#if PHP_VERSION_ID < 80100
#define ZEND_HASH_MAP_FOREACH_PTR ZEND_HASH_FOREACH_PTR

#ifndef PHP_STREAM_FLAG_NO_RSCR_DTOR_CLOSE
#define PHP_STREAM_FLAG_NO_RSCR_DTOR_CLOSE 0
#endif
#endif
```

### 2. `frankenphp.c` - Auto globals traversal

Use `zend_string_equals_literal()` instead of pointer comparison for PHP 8.0:

```c
#if PHP_VERSION_ID >= 80100
    if (auto_global->name == _env) {
#else
    if (zend_string_equals_literal(auto_global->name, "_ENV")) {
#endif
```

### 3. `frankenphp.c` - php_module_startup

PHP 8.0 requires 3 arguments:

```c
#if PHP_VERSION_ID >= 80100
  return php_module_startup(sapi_module, &frankenphp_module);
#else
  return php_module_startup(sapi_module, &frankenphp_module, 1);
#endif
```

### 4. `frankenphp.c` - file_handle.primary_script

This field doesn't exist in PHP 8.0:

```c
#if PHP_VERSION_ID >= 80100
  file_handle.primary_script = 1;
#endif
```

### 5. `types.c` - HashTable arPacked

PHP 8.0 uses `arData` for packed arrays:

```c
#if PHP_VERSION_ID >= 80100
    return &ht->arPacked[index];
#else
    return &ht->arData[index].val;
#endif
```

## PHP 8.0 Limitations

When running FrankenPHP with PHP 8.0, the following limitations apply:

1. **No Zend Max Execution Timers**: Timeout functionality (`max_execution_time`) is automatically disabled
2. **No `primary_script` tracking**: The primary script flag is not set (minor impact)
3. **No stream resource close flag**: `PHP_STREAM_FLAG_NO_RSCR_DTOR_CLOSE` is not applied

These limitations do not affect core functionality but may impact some edge cases.

## Version Compatibility Matrix

| PHP Version | FrankenPHP Support | Notes |
|-------------|-------------------|-------|
| 8.0.x | Supported | Requires source patches, no timeout support |
| 8.1.x | Supported | Full functionality |
| 8.2.x | Supported | Full functionality |
| 8.3.x | Supported | Full functionality |
| 8.4.x | Supported | Full functionality |

## Additional Resources

- [FrankenPHP Documentation](https://frankenphp.dev/)
- [PHP Downloads](https://www.php.net/downloads.php)
- [Building PHP from Source](https://www.php.net/manual/en/install.unix.php)
