#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <wincrypt.h>
#include <bcrypt.h>
#include <stdlib.h>
#include <string.h>
#include "include/winshim.h"

/* Only the current user's DPAPI context, with all interactive prompts disabled. */
static int unprotect(const unsigned char *bytes, int length, DATA_BLOB *output) {
    if (!bytes || length <= 0 || length > 65536) return 0;
    DATA_BLOB input={(DWORD)length,(BYTE*)bytes};
    return CryptUnprotectData(&input,NULL,NULL,NULL,NULL,CRYPTPROTECT_UI_FORBIDDEN,output) ? 1 : 0;
}
int win_decrypt_electron_secret(const unsigned char *cipher, int length,
    const unsigned char *wrapped_key, int key_length, unsigned char *output, int capacity, int *written) {
    if(written)*written=0;
    if(!cipher||!output||!written||length<=0||length>65536||capacity<=0)return 0;
    if(length<3||memcmp(cipher,"v10",3)!=0){
        /* Legacy user-DPAPI blobs only. v20/app-bound formats are not bypassed. */
        if(length<4||cipher[0]!=1||cipher[1]!=0||cipher[2]!=0||cipher[3]!=0)return 0;
        DATA_BLOB plain={0};if(!unprotect(cipher,length,&plain))return 0;
        int valid=plain.cbData<=(DWORD)capacity;
        if(valid){memcpy(output,plain.pbData,plain.cbData);*written=(int)plain.cbData;}
        SecureZeroMemory(plain.pbData,plain.cbData);LocalFree(plain.pbData);return valid;
    }
    if(length<31||!wrapped_key||key_length<=5||memcmp(wrapped_key,"DPAPI",5)!=0)return 0;
    DATA_BLOB key={0};if(!unprotect(wrapped_key+5,key_length-5,&key))return 0;
    BCRYPT_ALG_HANDLE algorithm=NULL;BCRYPT_KEY_HANDLE handle=NULL;BYTE *object=NULL;ULONG object_length=0,got=0,result=0;int success=0;
    if(key.cbData!=32)goto done;
    if(BCryptOpenAlgorithmProvider(&algorithm,BCRYPT_AES_ALGORITHM,NULL,0)<0)goto done;
    if(BCryptSetProperty(algorithm,BCRYPT_CHAINING_MODE,(PUCHAR)BCRYPT_CHAIN_MODE_GCM,sizeof(BCRYPT_CHAIN_MODE_GCM),0)<0)goto done;
    if(BCryptGetProperty(algorithm,BCRYPT_OBJECT_LENGTH,(PUCHAR)&object_length,sizeof(object_length),&got,0)<0)goto done;
    object=(BYTE*)calloc(1,object_length);if(!object)goto done;
    if(BCryptGenerateSymmetricKey(algorithm,&handle,object,object_length,key.pbData,key.cbData,0)<0)goto done;
    BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO info;BCRYPT_INIT_AUTH_MODE_INFO(info);
    info.pbNonce=(PUCHAR)cipher+3;info.cbNonce=12;info.pbTag=(PUCHAR)cipher+length-16;info.cbTag=16;
    if(BCryptDecrypt(handle,(PUCHAR)cipher+15,(ULONG)(length-31),&info,NULL,0,output,(ULONG)capacity,&result,0)<0)goto done;
    *written=(int)result;success=1;
 done:
    if(handle)BCryptDestroyKey(handle);if(object){SecureZeroMemory(object,object_length);free(object);}if(algorithm)BCryptCloseAlgorithmProvider(algorithm,0);
    SecureZeroMemory(key.pbData,key.cbData);LocalFree(key.pbData);return success;
}
