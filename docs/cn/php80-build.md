# 使用 PHP 8.0 构建 FrankenPHP

本文档介绍如何从源码构建支持 PHP 8.0 的 FrankenPHP。由于大多数包管理器不提供同时启用 ZTS（Zend 线程安全）和 embed SAPI 的 PHP 8.0，因此需要从源码构建 PHP。

> **注意**: 使用 PHP 8.0 时，Zend Max Execution Timers 不可用，因此超时功能（如 `max_execution_time`）将自动禁用。建议使用 PHP 8.1+ 以获得完整功能。

## 快速开始（自动化构建）

使用提供的构建脚本进行全自动构建：

```bash
# 默认构建（PHP 8.0.30）
./build-php80.sh

# 指定 PHP 版本
./build-php80.sh --php-version 8.0.28

# 清理后重新构建
./build-php80.sh --clean

# 跳过 PHP 构建（如已构建）
./build-php80.sh --skip-php-build
```

## 手动构建流程

### 前置依赖

#### macOS

通过 Homebrew 安装依赖：

```bash
brew install libiconv bison re2c pkg-config brotli openssl@1.1 go

# 将 bison 添加到 PATH
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

### 步骤 1: 下载并解压 PHP 源码

```bash
# 创建构建目录
mkdir -p ~/php-build && cd ~/php-build

# 下载 PHP 8.0.30
wget https://www.php.net/distributions/php-8.0.30.tar.gz

# 解压
tar xf php-8.0.30.tar.gz
cd php-8.0.30
```

### 步骤 2: 配置 PHP

#### macOS 配置

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

#### Linux 配置

```bash
./configure \
    --enable-embed=static \
    --enable-zts \
    --disable-zend-signals \
    --disable-opcache-jit \
    --enable-static \
    --enable-shared=no
```

### 步骤 3: 编译 PHP

```bash
# 使用所有可用 CPU 核心编译
make -j$(nproc)

# 验证构建
./sapi/cli/php -v
# 应显示: PHP 8.0.30 (cli) (...) ( ZTS )
```

### 步骤 4: 验证 PHP 构建

检查必需文件是否存在：

```bash
# 静态库（必需）
ls -la libs/libphp.a

# PHP CLI 二进制文件
ls -la sapi/cli/php

# Embed SAPI 头文件
ls -la sapi/embed/php_embed.h
```

### 步骤 5: 构建 FrankenPHP

进入 FrankenPHP 源码目录并构建：

```bash
cd /path/to/frankenphp/caddy/frankenphp

# 设置 PHP 构建路径
export PHP_BUILD=~/php-build/php-8.0.30
```

#### macOS 构建

```bash
CGO_CFLAGS="-I${PHP_BUILD}/include -I${PHP_BUILD}/main -I${PHP_BUILD} -I${PHP_BUILD}/TSRM -I${PHP_BUILD}/Zend -I${PHP_BUILD}/sapi/embed -I/opt/homebrew/include" \
CGO_LDFLAGS="-L${PHP_BUILD}/libs -lphp -L/opt/homebrew/opt/libiconv/lib -liconv -lresolv -lm -lpthread -lxml2 -lsqlite3 -lssl -lcrypto -L/opt/homebrew/lib -lbrotlienc -lbrotlidec -lbrotlicommon" \
go build -tags=nobadger,nomysql,nopgx,nowatcher
```

#### Linux 构建

```bash
CGO_CFLAGS="-I${PHP_BUILD}/include -I${PHP_BUILD}/main -I${PHP_BUILD} -I${PHP_BUILD}/TSRM -I${PHP_BUILD}/Zend -I${PHP_BUILD}/sapi/embed" \
CGO_LDFLAGS="-L${PHP_BUILD}/libs -lphp -lresolv -lm -lpthread -lxml2 -lsqlite3 -lssl -lcrypto -lbrotlienc -lbrotlidec -lbrotlicommon" \
go build -tags=nobadger,nomysql,nopgx,nowatcher
```

### 步骤 6: 验证 FrankenPHP 构建

```bash
# 检查版本
./frankenphp version

# 检查嵌入的 PHP 版本
./frankenphp php-cli -r 'echo PHP_VERSION . " " . (PHP_ZTS ? "ZTS" : "NTS") . "\n";'
# 预期输出: 8.0.30 ZTS

# 运行测试脚本
echo '<?php echo "Hello from FrankenPHP with PHP 8.0!";' > /tmp/test.php
./frankenphp php-cli /tmp/test.php
```

## 构建标签参考

| 标签 | 说明 |
|-----|------|
| `nobadger` | 禁用 BadgerDB 存储 |
| `nomysql` | 禁用 MySQL 存储 |
| `nopgx` | 禁用 PostgreSQL 存储 |
| `nowatcher` | 禁用文件监控（热重载） |
| `nobrotli` | 禁用 Brotli 压缩 |

## 故障排除

### 错误: `php_embed.h` 未找到

此错误发生在 PHP 未启用 embed SAPI 编译时。确保配置 PHP 时使用了 `--enable-embed=static`。

### 错误: `ZEND_STR_AUTOGLOBAL_ENV` 未声明

此错误发生在使用未修改的 FrankenPHP 源码针对 PHP 8.0 构建时。FrankenPHP 源码需要 PHP 8.0 兼容性补丁。

### 错误: `arPacked` 成员未找到

`HashTable` 中的 `arPacked` 字段是在 PHP 8.1 引入的。PHP 8.0 对于打包数组使用 `arData`。FrankenPHP 源码需要针对 PHP 8.0 兼容性进行修补。

### 链接器关于重复库的警告

这些警告无害，可以忽略：
```
ld: warning: ignoring duplicate libraries: '-lxml2', '-lssl', ...
```

## PHP 8.0 兼容性补丁

FrankenPHP 需要以下 C 代码修改以支持 PHP 8.0：

### 1. `frankenphp.c` - 添加兼容性宏

在 includes 之后添加：

```c
/* PHP 8.0 兼容性宏 */
#if PHP_VERSION_ID < 80100
#define ZEND_HASH_MAP_FOREACH_PTR ZEND_HASH_FOREACH_PTR

#ifndef PHP_STREAM_FLAG_NO_RSCR_DTOR_CLOSE
#define PHP_STREAM_FLAG_NO_RSCR_DTOR_CLOSE 0
#endif
#endif
```

### 2. `frankenphp.c` - Auto globals 遍历

PHP 8.0 使用 `zend_string_equals_literal()` 替代指针比较：

```c
#if PHP_VERSION_ID >= 80100
    if (auto_global->name == _env) {
#else
    if (zend_string_equals_literal(auto_global->name, "_ENV")) {
#endif
```

### 3. `frankenphp.c` - php_module_startup

PHP 8.0 需要 3 个参数：

```c
#if PHP_VERSION_ID >= 80100
  return php_module_startup(sapi_module, &frankenphp_module);
#else
  return php_module_startup(sapi_module, &frankenphp_module, 1);
#endif
```

### 4. `frankenphp.c` - file_handle.primary_script

此字段在 PHP 8.0 中不存在：

```c
#if PHP_VERSION_ID >= 80100
  file_handle.primary_script = 1;
#endif
```

### 5. `types.c` - HashTable arPacked

PHP 8.0 对打包数组使用 `arData`：

```c
#if PHP_VERSION_ID >= 80100
    return &ht->arPacked[index];
#else
    return &ht->arData[index].val;
#endif
```

## PHP 8.0 功能限制

使用 PHP 8.0 运行 FrankenPHP 时，以下功能受限：

1. **无 Zend Max Execution Timers**: 超时功能（`max_execution_time`）自动禁用
2. **无 `primary_script` 跟踪**: 主脚本标志未设置（影响较小）
3. **无流资源关闭标志**: `PHP_STREAM_FLAG_NO_RSCR_DTOR_CLOSE` 不应用

这些限制不影响核心功能，但可能影响某些边缘情况。

## 版本兼容性矩阵

| PHP 版本 | FrankenPHP 支持 | 备注 |
|---------|----------------|------|
| 8.0.x | 支持 | 需要源码补丁，无超时支持 |
| 8.1.x | 支持 | 完整功能 |
| 8.2.x | 支持 | 完整功能 |
| 8.3.x | 支持 | 完整功能 |
| 8.4.x | 支持 | 完整功能 |

## 其他资源

- [FrankenPHP 文档](https://frankenphp.dev/)
- [PHP 下载](https://www.php.net/downloads.php)
- [从源码构建 PHP](https://www.php.net/manual/zh/install.unix.php)
