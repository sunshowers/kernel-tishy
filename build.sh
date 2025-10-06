#!/bin/bash

#
# Key preparation
#

# Use two keys. In the action, these will get prefilled with the public
# keys from this directory

mkdir -p certs
for key in 101 102; do
    if [ ! -f certs/ubmok$key.priv ] || [ ! -f certs/ubmok$key.der ]; then
        echo "!! Warning. Creating ubmok$key for test build."
        openssl req -new -x509 -newkey rsa:2048 -keyout certs/ubmok$key.priv -out certs/ubmok$key.der -nodes -days 36500 -subj "/CN=ubluetestkey$key/"
    fi

    # Create pkcs12 file
    if [ ! -f certs/ubmok$key.p12 ]; then
        openssl pkcs12 -export -out certs/ubmok$key.p12 -inkey certs/ubmok$key.priv -in certs/ubmok$key.der -passout pass:
    fi
done


# Create NSS database and enroll keys
rm -rf ./certs/pki/ubluesign
mkdir -p ./certs/pki/ubluesign
certutil -N -d sql:./certs/pki/ubluesign --empty-password

# Import pkcs12 files
for key in 101 102; do
    certutil -A -d sql:./certs/pki/ubluesign -n "ubmok$key" -t "CT,C,C" -i certs/ubmok$key.der
    pk12util -i certs/ubmok$key.p12 -d sql:./certs/pki/ubluesign -W ""
done

# List keys
echo "Secure Boot Key status:"
certutil -L -d sql:./certs/pki/ubluesign

#
# Build
#

ARCH=${ARCH:-x86_64}
FEDORA_VERSION=${FEDORA_VERSION:-43}

echo "Starting build for Fedora $FEDORA_VERSION, arch $ARCH"

sudo rm -rf /etc/pki/pesign
sudo mkdir -p /etc/pki/pesign
sudo cp -r certs/pki/ubluesign /etc/pki/pesign

rpmbuild \
  --define '_topdir   %(pwd)/build' \
  --define '_builddir %{_topdir}/BUILD' \
  --define '_rpmdir   %{_topdir}/RPMS' \
  --define '_srcrpmdir %{_topdir}/SRPMS' \
  --define "_sourcedir $(pwd)/" \
  --define "_specdir  $(pwd)/" \
  --with bazzite --with ubsb --with nvidia --with zfs \
  -ba kernel.spec &

trap 'pkill --signal=SIGKILL -P $$; exit 130' INT
wait