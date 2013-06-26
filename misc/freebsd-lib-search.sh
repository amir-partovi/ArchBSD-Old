#!/bin/sh

#########################################################
# Find all binary files in world that is linked against #
# a specific library. Useful for finding packages which #
# Need rebuild when splitting librarys from world       #                                   
#########################################################


match=$1

if [ -z $match ]; then
  echo 'Usage: freebsd-lib-search <libname>'
  echo ''
  echo 'Find packages that depend on a given library.'
  echo 'E.G freebsd-lib-search libarchive.so.3'
  echo ''
  exit 1
fi

for file in \
`find /bin /usr/bin /sbin /usr/sbin /lib /usr/lib/ /usr/local/lib -type f -print0 | xargs -0 file | grep ELF | awk  -F ":" '{print $1}'`; do
      readelf -dW $file 2> /dev/null | sed -ne '/NEEDED/{s/^.*\[\(.*\)\]$/\1/;p;}' | grep $match > /dev/null 2>&1;
      if [ $? -eq 0 ]; then 
        echo $file depends on $match; 
        pacman -Qo $file;
      fi; 
done 
