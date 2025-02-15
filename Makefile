TARGET := riscv64-unknown-linux-gnu
CC := $(TARGET)-gcc
LD := $(TARGET)-gcc
OBJCOPY := $(TARGET)-objcopy
CFLAGS := -fPIC -O3 -fno-builtin-printf -fno-builtin-memcmp -nostdinc -nostdlib -nostartfiles -fvisibility=hidden -fdata-sections -ffunction-sections -I deps/secp256k1-20210801/src -I deps/secp256k1-20210801 -I deps/ckb-c-stdlib-2023 -I deps/ckb-c-stdlib-2023/libc -I deps/ckb-c-stdlib-2023/molecule -I c -I build -Wall -Werror -Wno-nonnull -Wno-nonnull-compare -Wno-unused-function -Wno-dangling-pointer -g
LDFLAGS := -Wl,-static -fdata-sections -ffunction-sections -Wl,--gc-sections
SECP256K1_SRC_20210801 := deps/secp256k1-20210801/src/ecmult_static_pre_context.h
AUTH_CFLAGS := $(CFLAGS) -I deps/mbedtls/include

# RSA/mbedtls
CFLAGS_MBEDTLS := $(subst ckb-c-std-lib,ckb-c-stdlib-2023,$(CFLAGS)) -I deps/mbedtls/include
LDFLAGS_MBEDTLS := $(LDFLAGS)
PASSED_MBEDTLS_CFLAGS := -O3 -fPIC -nostdinc -nostdlib -DCKB_DECLARATION_ONLY -I ../../ckb-c-stdlib-2023/libc -fdata-sections -ffunction-sections

# docker pull nervos/ckb-riscv-gnu-toolchain:gnu-jammy-20230214
BUILDER_DOCKER := nervos/ckb-riscv-gnu-toolchain@sha256:d3f649ef8079395eb25a21ceaeb15674f47eaa2d8cc23adc8bcdae3d5abce6ec

all:  build/secp256k1_data_info_20210801.h $(SECP256K1_SRC_20210801) deps/mbedtls/library/libmbedcrypto.a build/auth build/always_success

all-via-docker: ${PROTOCOL_HEADER}
	docker run --rm -v `pwd`:/code ${BUILDER_DOCKER} bash -c "cd /code && make"

build/always_success: c/always_success.c
	$(CC) $(AUTH_CFLAGS) $(LDFLAGS) -o $@ $<
	$(OBJCOPY) --only-keep-debug $@ $@.debug
	$(OBJCOPY) --strip-debug --strip-all $@


build/secp256k1_data_info_20210801.h: build/dump_secp256k1_data_20210801
	$<

build/dump_secp256k1_data_20210801: c/dump_secp256k1_data_20210801.c $(SECP256K1_SRC_20210801)
	mkdir -p build
	gcc -I deps/ckb-c-stdlib-2023 -I deps/secp256k1-20210801/src -I deps/secp256k1-20210801 -o $@ $<

$(SECP256K1_SRC_20210801):
	cd deps/secp256k1-20210801 && \
		./autogen.sh && \
		CC=$(CC) LD=$(LD) ./configure --with-bignum=no --enable-ecmult-static-precomputation --enable-endomorphism --enable-module-recovery --host=$(TARGET) && \
		make src/ecmult_static_pre_context.h src/ecmult_static_context.h

deps/mbedtls/library/libmbedcrypto.a:
	cp deps/mbedtls-config-template.h deps/mbedtls/include/mbedtls/config.h
	make -C deps/mbedtls/library CC=${CC} LD=${LD} CFLAGS="${PASSED_MBEDTLS_CFLAGS}" libmbedcrypto.a

build/auth: c/auth.c deps/mbedtls/library/libmbedcrypto.a
	$(CC) $(AUTH_CFLAGS) $(LDFLAGS) -fPIC -fPIE -pie -Wl,--dynamic-list c/auth.syms -o $@ $^
	cp $@ $@.debug
	$(OBJCOPY) --strip-debug --strip-all $@

fmt:
	clang-format -i -style="{BasedOnStyle: Google, IndentWidth: 4}" c/*.c c/*.h

clean:
	rm -rf build/*.debug
	rm -f build/auth build/auth_demo
	rm -rf build/secp256k1_data_info_20210801.h build/dump_secp256k1_data_20210801
	cd deps/secp256k1-20210801 && [ -f "Makefile" ] && make clean
	make -C deps/mbedtls/library clean

.PHONY: all all-via-docker

