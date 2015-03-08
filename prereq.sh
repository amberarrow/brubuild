#!/bin/bash

# script for debian package based systems (like Ubuntu) to download and
# install these prerequisites for Brubuild:
#
#  libbz2-dev           [TokyoCabinet pre-requisite]
#  zlib1g-dev           [Ruby pre-requisite for some features]
#  libreadline6-dev     [Ruby pre-requisite for some features]
#  libffi-dev           [Ruby pre-requisite for some features]        
#  libyaml-dev          [Ruby pre-requisite for some features]
#  tokyocabinet         [for persistence]
#  tokyocabinet-ruby    [for persistence]
#
# usage:
#     bash prereq.sh [install-dir]
# where install-dir is the directory where where ruby and tokyocabinet will be installed
# source archives are unpacked in the current directory, so you should to the appropriate
# directory before running this script.
# 

set -e    # exit if we encounter errors

sudo apt-get install libbz2-dev zlib1g-dev libreadline6-dev libyaml-dev libffi-dev

if [[ -n "$1" ]]; then
    prefix="$1"
else
    prefix=/use/local
fi
[[ -d "$prefix" ]] || mkdir -p "$prefix"

# top-level directories from tarballs
rb_dir=ruby-2.2.1   tc_dir=tokyocabinet-1.4.47   tcr_dir=tokyocabinet-ruby-1.31

# change to false if the archives are already downloaded and unpacked
if /bin/true; then
    # fetch tarballs and extract
    rb="$rb_dir.tar.gz" tc="$tc_dir.tar.gz" tcr="$tcr_dir.tar.gz"

    wget http://ftp.ruby-lang.org/pub/ruby/2.2.1/"$rb"
    wget http://fallabs.com/tokyocabinet/"$tc"
    wget http://fallabs.com/tokyocabinet/rubypkg/"$tcr"

    for f in "$rb" "$tc" "$tcr"; do tar xvf "$f"; done
fi

chkdir ( ) {    # check that each argument directory exists
    for d in "$@"; do
        [[ -d "$d" ] && continue
        echo "Directory $d not found"; exit 1
    done
}

chkdir "$rb_dir" "$tc_dir" "$tcr_dir"

cd "$rb_dir"      # make ruby
./configure --prefix=$prefix
make; make install
echo "Installed Ruby 2.2.1 in $prefix"

cd ../$tc_dir     # make tokyocabinet
./configure --prefix=$prefix
make; make install
echo "Installed Tokyo Cabinet in $prefix"

cd ../$tcr_dir    # make tokyocabinet ruby bindings
$prefix/bin/ruby extconf.rb --with-tokyocabinet-dir=$prefix
make; make install
echo "Installed Tokyo Cabinet Ruby bindings in $prefix"

echo Done
