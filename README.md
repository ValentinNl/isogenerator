# Ubuntu Autoinstall Generator

This repository is forked from https://github.com/covertsh/ubuntu-autoinstall-generator

##Prerequisities
XORRISO
ISOLINUX
SED
last ubuntu server 20.04 release

## Build your own iso
1. Write your user-data file
2. execute : $ bash ubuntu-autoinstall-generator.sh -u user-data -s ubuntu-server-20.04.iso -d custom_u20.iso
3. create your own bootable usb device
