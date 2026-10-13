#!/bin/bash

./configure --prefix=/usr     \
            --sysconfdir=/etc \
            --disable-static  &&
make -j12 && make install
