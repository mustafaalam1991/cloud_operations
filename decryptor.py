from cryptography.fernet import Fernet

import sys
from encryptor import *

homeDir='/home/stack/'
file2decrypt = str(sys.argv[1])

encryptor=Encryptor()

encryptor.file_decrypt(loaded_key, homeDir+file2decrypt+'.enc', homeDir+file2decrypt+'.dec')
