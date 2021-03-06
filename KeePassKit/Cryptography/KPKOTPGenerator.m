//
//  KPKOTP.m
//  KeePassKit
//
//  Created by Michael Starke on 09.12.17.
//  Copyright © 2017 HicknHack Software GmbH. All rights reserved.
//

#import "KPKOTPGenerator.h"
#import <CommonCrypto/CommonCrypto.h>

@implementation NSData (KPKOTPDataConversion)

- (NSUInteger)unsignedInteger {
  /*
   HMAC data is interpreted as big endian
   */
  NSUInteger number = 0;
  [self getBytes:&number length:MIN(self.length, sizeof(NSUInteger))];
  
  /*
   convert big endian to host
   if conversion took place, we need to shift by the size
   */
#if __LP64__ || NS_BUILD_32_LIKE_64
  NSUInteger beNumber = (NSUInteger)CFSwapInt64BigToHost(number);
#else
  NSUInteger beNumber = (NSUInteger)CFSwapInt32BigToHost(number);
#endif
  
  if(beNumber != number) {
    beNumber >>= (8 * (sizeof(NSUInteger) - self.length));
  }
  return beNumber;
}

@end

@interface KPKOTPGenerator ()

@property (readonly, copy) NSString *alphabet;

@end

@implementation KPKOTPGenerator

- (instancetype)init {
  self = [super init];
  if(self) {
    _hashAlgorithm = KPKOTPHashAlgorithmSha1;
    _key = [NSData.data copy]; // use an empty key;
    _type = KPKOTPGeneratorHmacOTP;
    _timeBase = 0;
    _timeSlice = 30;
    _time = 0;
    _counter = 0;
    _numberOfDigits = 6;
  }
  return self;
}

- (NSString *)alphabet {
  switch (self.type) {
    case KPKOTPGeneratorHmacOTP:
    case KPKOTPGeneratorTOTP:
      return @"0123456789";
      
    case KPKOTPGeneratorSteamOTP:
      return @"23456789BCDFGHJKMNPQRTVWXY";
    default:
      return @"";
      break;
  }
}

- (NSData *)data {
  if(![self _validateOptions]) {
    return NSData.data;
  }
  if(self.type == KPKOTPGeneratorTOTP) {
    self.counter = floor((self.time - self.timeBase) / self.timeSlice);
  }
  return [self _HMACOTPWithKey:self.key counter:self.counter algorithm:self.hashAlgorithm];
}

- (NSString *)string {
  NSData *data = self.data;
  if(data.length == 0) {
    return @""; // invalid data
  }
  
  NSUInteger decimal = data.unsignedInteger;
  NSUInteger alphabetLength = self.alphabet.length;
  NSMutableString *result = [[NSMutableString alloc] init];
  while(result.length < self.numberOfDigits) {
    NSUInteger code = decimal % alphabetLength;
    if(code < alphabetLength) {
      [result insertString:[self.alphabet substringWithRange:NSMakeRange(code, 1)] atIndex:0];
    }
    else {
      return @""; // falure
    }
    decimal /= alphabetLength;
  }
  return [result copy];
}

- (BOOL)_validateOptions {
  return (self.numberOfDigits >= 1 &&
          self.numberOfDigits <= 8 &&
          self.key.length > 0
          );
}

- (NSData *)_HMACOTPWithKey:(NSData *)key counter:(uint64_t)counter algorithm:(KPKOTPHashAlgorithm)algorithm {
  // ensure we use big endian
  uint64_t beCounter = CFSwapInt64HostToBig(counter);
  
  uint8_t digestLenght = CC_SHA1_DIGEST_LENGTH;
  CCHmacAlgorithm hashAlgorithm = kCCHmacAlgSHA1;
  switch(algorithm) {
    case KPKOTPHashAlgorithmSha1:
      break; // nothing to do
    case KPKOTPHashAlgorithmSha256:
      hashAlgorithm = kCCHmacAlgSHA256;
      digestLenght = CC_SHA256_DIGEST_LENGTH;
      break;
    case KPKOTPHashAlgorithmSha512:
      hashAlgorithm = kCCHmacAlgSHA512;
      digestLenght = CC_SHA512_DIGEST_LENGTH;
      break;
    default:
      // should not happen
      return nil;
      break;
  }
  
  uint8_t mac[digestLenght];
  CCHmac(hashAlgorithm, key.bytes, key.length, &beCounter, sizeof(uint64_t), mac);
  
  /* offset is lowest 4 bit on last byte */
  uint8_t offset = (mac[digestLenght - 1] & 0x0f);
  
  uint8_t otp[4];
  otp[0] = mac[offset] & 0x7f;
  otp[1] = mac[offset + 1];
  otp[2] = mac[offset + 2];
  otp[3] = mac[offset + 3];
  
  return [NSData dataWithBytes:&otp length:sizeof(uint32_t)];
}


@end
