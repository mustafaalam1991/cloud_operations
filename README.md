# cloud_operations
This repo is all things related to openstack cloud operations. I have added some administrative guides and ppts related to ceph storage for now. Hope you ind them helpfull. feedback is welcome! 



# Usage: encryptor and decryptor
The python script are built using cryptography.fernet library in python 

Pre-requisite: 
  pip install cryptography

Two script files: 
  1. encryptor.py
  2. decryptor.py

Usage (1) encryptor.py 
  ## Below command takes a plain-text file as an argument and creates an encrypted file with extension .enc 
  sudo python encryptor.py <file_name>
  ## Below command takes an encrypted file as an argument and generates a decrypted file with extension .dec 
  sudo python decryptor.py <file_name>
