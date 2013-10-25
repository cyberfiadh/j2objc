// Copyright 2011 Google Inc. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

//
//  IOSClass.m
//  JreEmulation
//
//  Created by Tom Ball on 10/18/11.
//

#import "IOSClass.h"
#import "java/lang/AssertionError.h"
#import "java/lang/ClassCastException.h"
#import "java/lang/ClassLoader.h"
#import "java/lang/ClassNotFoundException.h"
#import "java/lang/Enum.h"
#import "java/lang/InstantiationException.h"
#import "java/lang/NoSuchFieldException.h"
#import "java/lang/NoSuchMethodException.h"
#import "java/lang/NullPointerException.h"
#import "java/lang/Package.h"
#import "java/lang/annotation/Annotation.h"
#import "java/lang/annotation/Inherited.h"
#import "java/lang/reflect/Constructor.h"
#import "java/lang/reflect/Field.h"
#import "java/lang/reflect/Method.h"
#import "java/lang/reflect/Modifier.h"
#import "IOSArray.h"
#import "IOSArrayClass.h"
#import "IOSBooleanArray.h"
#import "IOSByteArray.h"
#import "IOSCharArray.h"
#import "IOSConcreteClass.h"
#import "IOSDoubleArray.h"
#import "IOSFloatArray.h"
#import "IOSIntArray.h"
#import "IOSLongArray.h"
#import "IOSObjectArray.h"
#import "IOSPrimitiveClass.h"
#import "IOSProtocolClass.h"
#import "IOSShortArray.h"
#import "JavaMetadata.h"
#import "objc/runtime.h"

@implementation IOSClass

static NSDictionary *IOSClass_mappedClasses;

// Primitive class instances.
static IOSPrimitiveClass *IOSClass_byteClass;
static IOSPrimitiveClass *IOSClass_charClass;
static IOSPrimitiveClass *IOSClass_doubleClass;
static IOSPrimitiveClass *IOSClass_floatClass;
static IOSPrimitiveClass *IOSClass_intClass;
static IOSPrimitiveClass *IOSClass_longClass;
static IOSPrimitiveClass *IOSClass_shortClass;
static IOSPrimitiveClass *IOSClass_booleanClass;
static IOSPrimitiveClass *IOSClass_voidClass;

// Other commonly used instances.
static IOSClass *IOSClass_objectClass;

// Function forwards.
static IOSClass *FetchClass(Class cls);
static IOSClass *FetchProtocol(Protocol *protocol);
static IOSClass *FetchArray(IOSClass *componentType);

- (id)init {
  if ((self = [super init])) {
    JreMemDebugAdd(self);
  }
  return self;
}

- (Class)objcClass {
  return nil;
}

- (Protocol *)objcProtocol {
  return nil;
}

+ (IOSClass *)classWithClass:(Class)cls {
  return FetchClass(cls);
}

+ (IOSClass *)classWithProtocol:(Protocol *)protocol {
  return FetchProtocol(protocol);
}

+ (IOSClass *)arrayClassWithComponentType:(IOSClass *)componentType {
  return FetchArray(componentType);
}

+ (IOSClass *)byteClass {
  return IOSClass_byteClass;
}

+ (IOSClass *)charClass {
  return IOSClass_charClass;
}

+ (IOSClass *)doubleClass {
  return IOSClass_doubleClass;
}

+ (IOSClass *)floatClass {
  return IOSClass_floatClass;
}

+ (IOSClass *)intClass {
  return IOSClass_intClass;
}

+ (IOSClass *)longClass {
  return IOSClass_longClass;
}

+ (IOSClass *)shortClass {
  return IOSClass_shortClass;
}

+ (IOSClass *)booleanClass {
  return IOSClass_booleanClass;
}

+ (IOSClass *)voidClass {
  return IOSClass_voidClass;
}

+ (IOSClass *)objectClass {
  return IOSClass_objectClass;
}

- (id)newInstance {
  // Per the JLS spec, throw an InstantiationException if the type is an
  // interface (no class_), array or primitive type (IOSClass types), or void.
  @throw AUTORELEASE([[JavaLangInstantiationException alloc] init]);
}

- (IOSClass *)getSuperclass {
  return nil;
}

// Returns true if an object is an instance of this class.
- (BOOL)isInstance:(id)object {
  return NO;
}

- (NSString *)getName {
  @throw AUTORELEASE([[JavaLangAssertionError alloc] initWithNSString:
      @"abstract method not overridden"]);
}

- (NSString *)getSimpleName {
  return [self getName];
}

- (NSString *)getCanonicalName {
  return [self getName];
}

- (NSString *)objcName {
  @throw AUTORELEASE([[JavaLangAssertionError alloc] initWithNSString:
      @"abstract method not overridden"]);
}

- (int)getModifiers {
  JavaClassMetadata *metadata = [self getMetadata];
  if (metadata) {
    return metadata.modifiers & [JavaLangReflectModifier classModifiers];
  } else {
    // All Objective-C classes and protocols are public by default.
    return JavaLangReflectModifier_PUBLIC;
  }
}

- (void)collectMethods:(NSMutableDictionary *)methodMap {
  // Overridden by subclasses.
}

// Return the class and instance methods declared by this class.  Superclass
// methods are not included.
- (IOSObjectArray *)getDeclaredMethods {
  NSMutableDictionary *methodMap = [NSMutableDictionary dictionary];
  [self collectMethods:methodMap];
  return [IOSObjectArray arrayWithNSArray:[methodMap allValues] type:
      FetchClass([JavaLangReflectMethod class])];
}

// Return the constructors declared by this class.  Superclass constructors
// are not included.
- (IOSObjectArray *)getDeclaredConstructors {
  return [IOSObjectArray arrayWithLength:0 type:
      FetchClass([JavaLangReflectConstructor class])];
}

// Return the methods for this class, including inherited methods.
- (IOSObjectArray *)getMethods {
  NSMutableDictionary *methodMap = [NSMutableDictionary dictionary];
  IOSClass *cls = self;
  while (cls) {
    [cls collectMethods:methodMap];
    cls = [cls getSuperclass];
  }
  return [IOSObjectArray arrayWithNSArray:[methodMap allValues] type:
      FetchClass([JavaLangReflectMethod class])];
}

// Return the constructors for this class, including inherited ones.
- (IOSObjectArray *)getConstructors {
  return [IOSObjectArray arrayWithLength:0 type:
      FetchClass([JavaLangReflectConstructor class])];
}

// Return a method instance described by a name and an array of
// parameter types.  If the named method isn't a member of the specified
// class, return a superclass method if available.
- (JavaLangReflectMethod *)getMethod:(NSString *)name
                      parameterTypes:(IOSObjectArray *)types {
  NSString *translatedName = IOSClass_GetTranslatedMethodName(name, types);
  JavaLangReflectMethod *method = [self findMethodWithTranslatedName:translatedName];
  if (method != nil) {
    return method;
  }
  IOSClass *cls = self;
  while ((cls = [cls getSuperclass]) != nil) {
    method = [cls findMethodWithTranslatedName:translatedName];
    if (method != nil) {
      return method;
    }
  }
  @throw AUTORELEASE([[JavaLangNoSuchMethodException alloc] initWithNSString:name]);
}

// Return a method instance described by a name and an array of parameter
// types.  Return nil if the named method is not a member of this class.
- (JavaLangReflectMethod *)getDeclaredMethod:(NSString *)name
                              parameterTypes:(IOSObjectArray *)types {
  JavaLangReflectMethod *result =
      [self findMethodWithTranslatedName:IOSClass_GetTranslatedMethodName(name, types)];
  if (!result) {
    @throw AUTORELEASE([[JavaLangNoSuchMethodException alloc] initWithNSString:name]);
  }
  return result;
}

- (JavaLangReflectMethod *)findMethodWithTranslatedName:(NSString *)objcName {
  return nil; // Overriden by subclasses.
}

static NSString *Capitalize(NSString *s) {
  if ([s length] == 0) {
    return s;
  }
  // Only capitalize the first character, as NSString.capitalizedString
  // will make all other characters lowercase.
  NSString *firstChar = [[s substringToIndex:1] capitalizedString];
  return [s stringByReplacingCharactersInRange:NSMakeRange(0, 1)
                                    withString:firstChar];
}

static NSString *GetParameterKeyword(IOSClass *paramType) {
  if (paramType == IOSClass_objectClass) {
    return @"Id";
  }
  return Capitalize([paramType objcName]);
}

// Return a method name as it would be modified during j2objc translation.
// The format is "name" with no parameters, "nameWithType:" for one parameter,
// and "nameWithType:withType:..." for multiple parameters.
NSString *IOSClass_GetTranslatedMethodName(NSString *name, IOSObjectArray *parameterTypes) {
  NSUInteger nParameters = [parameterTypes count];
  if (nParameters == 0) {
    return name;
  }
  IOSClass *firstParameterType = parameterTypes->buffer_[0];
  NSMutableString *translatedName = [NSMutableString stringWithCapacity:128];
  [translatedName appendFormat:@"%@With%@:", name, GetParameterKeyword(firstParameterType)];
  for (NSUInteger i = 1; i < nParameters; i++) {
    IOSClass *parameterType = parameterTypes->buffer_[i];
    [translatedName appendFormat:@"with%@:", GetParameterKeyword(parameterType)];
  }
  return translatedName;
}

- (IOSClass *)getComponentType {
  return nil;
}

- (JavaLangReflectConstructor *)getConstructor:(IOSObjectArray *)parameterTypes {
  // Java's getConstructor() only returns the constructor if it's public.
  // However, all constructors in Objective-C are public, so this method
  // is identical to getDeclaredConstructor().
  @throw AUTORELEASE([[JavaLangNoSuchMethodException alloc] init]);
}

- (JavaLangReflectConstructor *)getDeclaredConstructor:(IOSObjectArray *)parameterTypes {
  @throw AUTORELEASE([[JavaLangNoSuchMethodException alloc] init]);
}

- (BOOL)isAssignableFrom:(IOSClass *)cls {
  @throw AUTORELEASE([[JavaLangAssertionError alloc] initWithNSString:
      @"abstract method not overridden"]);
}

- (IOSClass *)asSubclass:(IOSClass *)cls {
  @throw AUTORELEASE([[JavaLangClassCastException alloc] init]);
}

- (NSString *)description {
  // matches java.lang.Class.toString() output
  return [NSString stringWithFormat:@"class %@", [self getName]];
}

- (NSString *)binaryName {
  return [self getName];
}

// Convert Java class name to camelcased iOS name.
static NSString *IOSClass_JavaToIOSName(NSString *javaName) {
  NSString *mappedName = [IOSClass_mappedClasses objectForKey:javaName];
  if (mappedName) {
    return mappedName;
  }
  NSArray *parts = [javaName componentsSeparatedByString:@"."];
  NSMutableString *iosName = [NSMutableString string];
  for (NSString *part in parts) {
    [iosName appendString:Capitalize(part)];
  }
  [iosName replaceOccurrencesOfString:@"$"
                           withString:@"_"
                              options:0
                                range:NSMakeRange(0, [iosName length])];
  return iosName;
}

static IOSClass *ClassForIosName(NSString *iosName) {
  // Some protocols have a sibling class that contains the metadata and any
  // constants that are defined. We must look for the protocol before the class
  // to ensure we create a IOSProtocolClass for such cases. NSObject must be
  // special-cased because it also has a protocol but we want to return an
  // IOSConcreteClass instance for it.
  if ([iosName isEqualToString:@"NSObject"]) {
    return [IOSClass objectClass];
  }
  Protocol *protocol = NSProtocolFromString(iosName);
  if (protocol) {
    return FetchProtocol(protocol);
  }
  Class clazz = NSClassFromString(iosName);
  if (clazz) {
    return FetchClass(clazz);
  }
  return nil;
}

+ (IOSClass *)classForIosName:(NSString *)iosName {
  return ClassForIosName(iosName);
}

static IOSClass *ClassForJavaName(NSString *name) {
  return ClassForIosName(IOSClass_JavaToIOSName(name));
}

static IOSClass *IOSClass_PrimitiveClassForChar(unichar c) {
  switch (c) {
    case 'B': return IOSClass_byteClass;
    case 'C': return IOSClass_charClass;
    case 'D': return IOSClass_doubleClass;
    case 'F': return IOSClass_floatClass;
    case 'I': return IOSClass_intClass;
    case 'J': return IOSClass_longClass;
    case 'S': return IOSClass_shortClass;
    case 'Z': return IOSClass_booleanClass;
    // void type purposfully excluded because you can't have a void array.
    default: return nil;
  }
}

static IOSClass *IOSClass_ArrayClassForName(NSString *name, NSUInteger index) {
  IOSClass *componentType = nil;
  unichar c = [name characterAtIndex:index];
  switch (c) {
    case 'L':
      {
        NSUInteger length = [name length];
        if ([name characterAtIndex:length - 1] == ';') {
          componentType = ClassForJavaName(
              [name substringWithRange:NSMakeRange(index + 1, length - index - 2)]);
        }
        break;
      }
    case '[':
      componentType = IOSClass_ArrayClassForName(name, index + 1);
      break;
    default:
      if ([name length] == index + 1) {
        componentType = IOSClass_PrimitiveClassForChar(c);
      }
      break;
  }
  if (componentType) {
    return FetchArray(componentType);
  }
  return nil;
}

+ (IOSClass *)forName:(NSString *)className {
  nil_chk(className);
  IOSClass *iosClass = nil;
  if ([className length] > 0) {
    if ([className characterAtIndex:0] == '[') {
      iosClass = IOSClass_ArrayClassForName(className, 1);
    } else {
      iosClass = ClassForJavaName(className);
    }
  }
  if (iosClass) {
    return iosClass;
  }
  @throw AUTORELEASE([[JavaLangClassNotFoundException alloc] init]);
}

+ (IOSClass *)forName:(NSString *)className
           initialize:(BOOL)load
          classLoader:(id)loader {
  return [IOSClass forName:className];
}

- (id)cast:(id)throwable {
  // There's no need to actually cast this here, as the translator will add
  // a C cast since the return type is a type variable.
  return throwable;
}

- (IOSClass *)getEnclosingClass {
  JavaClassMetadata *metadata = [self getMetadata];
  if (!metadata || !metadata.enclosingName) {
    return nil;
  }
  NSMutableString *qName = [NSMutableString string];
  if (metadata.packageName) {
    [qName appendString:metadata.packageName];
    [qName appendString:@"."];
  }
  [qName appendString:metadata.enclosingName];
  return ClassForJavaName(qName);
}

- (BOOL)isArray {
  return NO;
}

- (BOOL)isEnum {
  return NO;
}

- (BOOL)isInterface {
  return NO;
}

- (BOOL)isPrimitive {
  return NO;  // Overridden by IOSPrimitiveClass.
}

static BOOL hasModifier(IOSClass *cls, int flag) {
  JavaClassMetadata *metadata = [cls getMetadata];
  return metadata ? (metadata.modifiers & flag) > 0 : NO;
}

- (BOOL)isAnnotation {
  return hasModifier(self, JavaLangReflectModifier_ANNOTATION);
}

- (BOOL)isMemberClass {
  JavaClassMetadata *metadata = [self getMetadata];
  return metadata && metadata.enclosingName && ![self isAnonymousClass];
}

- (BOOL)isSynthetic {
  return hasModifier(self, JavaLangReflectModifier_SYNTHETIC);
}

- (IOSObjectArray *)getInterfacesWithArrayType:(IOSClass *)arrayType {
  return [IOSObjectArray arrayWithLength:0 type:arrayType];
}

- (IOSObjectArray *)getInterfaces {
  return [self getInterfacesWithArrayType:FetchClass([IOSClass class])];
}

- (IOSObjectArray *)getGenericInterfaces {
  return [self getInterfacesWithArrayType:FetchProtocol(@protocol(JavaLangReflectType))];
}

- (IOSObjectArray *)getTypeParameters {
  IOSClass *typeVariableClass = [IOSClass
      classWithProtocol:objc_getProtocol("JavaLangReflectTypeVariable")];
  return [IOSObjectArray arrayWithLength:0 type:typeVariableClass];
}

- (id)getAnnotationWithIOSClass:(IOSClass *)annotationClass {
  nil_chk(annotationClass);
  IOSObjectArray *annotations = [self getAnnotations];
  NSUInteger n = [annotations count];
  for (NSUInteger i = 0; i < n; i++) {
    id annotation = annotations->buffer_[i];
    if ([annotationClass isInstance:annotation]) {
      return annotation;
    }
  }
  return nil;
}

- (BOOL)isAnnotationPresentWithIOSClass:(IOSClass *)annotationClass {
  return [self getAnnotationWithIOSClass:annotationClass] != nil;
}

- (IOSObjectArray *)getAnnotations {
  NSMutableArray *array = [[NSMutableArray alloc] init];
  IOSObjectArray *declared = [self getDeclaredAnnotations];
  for (NSUInteger i = 0; i < [declared count]; i++) {
    [array addObject:declared->buffer_[i]];
  }

  // Check for any inherited annotations.
  IOSClass *cls = [self getSuperclass];
  IOSClass *inheritedAnnotation = [JavaLangAnnotationInheritedImpl getClass];
  while (cls) {
    IOSObjectArray *declared = [cls getDeclaredAnnotations];
    for (NSUInteger i = 0; i < [declared count]; i++) {
      id<JavaLangAnnotationAnnotation> annotation = declared->buffer_[i];
      IOSObjectArray *attributes = [[annotation getClass] getDeclaredAnnotations];
      for (NSUInteger j = 0; j < [attributes count]; j++) {
        id<JavaLangAnnotationAnnotation> attribute = attributes->buffer_[j];
        if (inheritedAnnotation == [attribute getClass]) {
          [array addObject:annotation];
        }
      }
    }
    cls = [cls getSuperclass];
  }
  IOSClass *annotationType = [IOSClass classWithProtocol:@protocol(JavaLangAnnotationAnnotation)];
  IOSObjectArray *result = [IOSObjectArray arrayWithNSArray:array type:annotationType];
#if ! __has_feature(objc_arc)
  [array release];
#endif
  return result;
}

- (IOSObjectArray *)getDeclaredAnnotations {
  IOSObjectArray *methods = [self getDeclaredMethods];
  NSUInteger n = [methods count];
  for (NSUInteger i = 0; i < n; i++) {
    JavaLangReflectMethod *method = methods->buffer_[i];
    if ([@"__annotations" isEqualToString:[method getName]] &&
        [[method getParameterTypes] count] == 0) {
      IOSObjectArray *noArgs = [IOSObjectArray arrayWithLength:0 type:[NSObject getClass]];
      return (IOSObjectArray *) [method invokeWithId:nil withNSObjectArray:noArgs];
    }
  }
  IOSClass *annotationType = [IOSClass classWithProtocol:@protocol(JavaLangAnnotationAnnotation)];
  return [IOSObjectArray arrayWithLength:0 type:annotationType];
}

// Returns the metadata structure defined by this class, if it exists.
- (JavaClassMetadata *)getMetadata {
  Class cls = [self objcClass];
  if (cls) {
    SEL sel = @selector(__metadata);
    if ([cls respondsToSelector:sel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
      J2ObjcClassInfo *rawData = (ARCBRIDGE J2ObjcClassInfo *) [cls performSelector:sel];
#pragma clang diagnostic pop
      return AUTORELEASE([[JavaClassMetadata alloc] initWithMetadata:rawData]);
    }
  }
  return nil;
}

- (id)getPackage {
  JavaClassMetadata *metadata = [self getMetadata];
  if (metadata) {
    return AUTORELEASE([[JavaLangPackage alloc] initWithNSString:metadata.packageName
                                                    withNSString:nil
                                                    withNSString:nil
                                                    withNSString:nil
                                                    withNSString:nil
                                                    withNSString:nil
                                                    withNSString:nil
                                                  withJavaNetURL:nil]);
  }
  return nil;
}

- (id)getClassLoader {
  return [JavaLangClassLoader getSystemClassLoader];
}

static const char* GetFieldName(NSString *name) {
  name = [JavaLangReflectField variableName:name];
  return [name cStringUsingEncoding:[NSString defaultCStringEncoding]];
}

// Adds all the fields for a specified class to a specified dictionary.
static void GetFieldsFromClass(IOSClass *iosClass, NSMutableDictionary *fields) {
  unsigned int count;
  Ivar *ivars = class_copyIvarList(iosClass.objcClass, &count);
  for (unsigned int i = 0; i < count; i++) {
    JavaLangReflectField *field = [JavaLangReflectField fieldWithIvar:ivars[i] withClass:iosClass];
    NSString *name = [field getName];
    if (![fields valueForKey:name]) { // Don't add shadowed fields.
      [fields setObject:field forKey:name];
    }
  }
  free(ivars);
}

// TODO(tball): add support for interface constants.
- (JavaLangReflectField *)getDeclaredField:(NSString *)name {
  nil_chk(name);
  Class cls = self.objcClass;
  if (cls) {
    Ivar ivar = class_getInstanceVariable(cls, GetFieldName(name));
    if (ivar) {
      return [JavaLangReflectField fieldWithIvar:ivar withClass:self];
    }
  }
  @throw AUTORELEASE([[JavaLangNoSuchFieldException alloc] initWithNSString:name]);
}

- (JavaLangReflectField *)getField:(NSString *)name {
  nil_chk(name);
  const char *objcName = GetFieldName(name);
  IOSClass *iosClass = self;
  Class cls = nil;
  while (iosClass && (cls = iosClass.objcClass)) {
    Ivar ivar = class_getInstanceVariable(cls, objcName);
    if (ivar) {
      return [JavaLangReflectField fieldWithIvar:ivar withClass:iosClass];
    }
    iosClass = [iosClass getSuperclass];
  }
  @throw AUTORELEASE([[JavaLangNoSuchFieldException alloc] initWithNSString:name]);
}

IOSObjectArray *copyFieldsToObjectArray(NSArray *fields) {
  NSUInteger count = [fields count];
  IOSClass *fieldType = [IOSClass classWithClass:[JavaLangReflectField class]];
  IOSObjectArray *results = [IOSObjectArray arrayWithLength:count
                                                       type:fieldType];
  for (NSUInteger i = 0; i < count; i++) {
    [results replaceObjectAtIndex:i withObject:[fields objectAtIndex:i]];
  }
  return results;
}

- (IOSObjectArray *)getDeclaredFields {
  NSMutableDictionary *fieldDictionary = [NSMutableDictionary dictionary];
  GetFieldsFromClass(self, fieldDictionary);
  return copyFieldsToObjectArray([fieldDictionary allValues]);
}

- (IOSObjectArray *)getFields {
  NSMutableDictionary *fieldDictionary = [NSMutableDictionary dictionary];
  IOSClass *iosClass = self;
  Class cls = nil;
  while (iosClass && (cls = iosClass.objcClass)) {
    GetFieldsFromClass(iosClass, fieldDictionary);
    iosClass = [iosClass getSuperclass];
  }
  return copyFieldsToObjectArray([fieldDictionary allValues]);
}

- (JavaLangReflectMethod *)getEnclosingMethod {
  return nil;  // Classes aren't enclosed in Objective-C.
}

- (JavaLangReflectMethod *)getEnclosingConstructor {
  return nil;  // Classes aren't enclosed in Objective-C.
}

- (BOOL)isAnonymousClass {
  return NO;
}

- (BOOL)desiredAssertionStatus {
  return false;
}

- (IOSObjectArray *)getEnumConstants {
  if ([self isEnum]) {
    return [JavaLangEnum getValuesWithIOSClass:self];
  }
  return nil;
}

- (JavaNetURL *)getResource:(NSString *)name {
  return [[self getClassLoader] getResourceWithNSString:name];
}

- (JavaIoInputStream *)getResourceAsStream:(NSString *)name {
  return [[self getClassLoader] getResourceAsStreamWithNSString:name];
}

// Implementing NSCopying allows IOSClass objects to be used as keys in the
// class cache.
- (id)copyWithZone:(NSZone *)zone {
  return self;
}

- (void)dealloc {
#if ! __has_feature(objc_arc)
  JreMemDebugRemove(self);
  [super dealloc];
#endif
}

IOSClass *FetchClass(Class cls) {
  static int key;
  IOSClass *iosClass = objc_getAssociatedObject(cls, &key);
  if (!iosClass) {
    @synchronized (cls) {
      iosClass = objc_getAssociatedObject(cls, &key);
      if (!iosClass) {
        iosClass = AUTORELEASE([[IOSConcreteClass alloc] initWithClass:cls]);
        objc_setAssociatedObject(cls, &key, iosClass, OBJC_ASSOCIATION_RETAIN);
      }
    }
  }
  return iosClass;
}

IOSClass *FetchProtocol(Protocol *protocol) {
  static int key;
  IOSClass *iosClass = objc_getAssociatedObject(protocol, &key);
  if (!iosClass) {
    @synchronized (protocol) {
      iosClass = objc_getAssociatedObject(protocol, &key);
      if (!iosClass) {
        iosClass = AUTORELEASE([[IOSProtocolClass alloc] initWithProtocol:protocol]);
        objc_setAssociatedObject(protocol, &key, iosClass, OBJC_ASSOCIATION_RETAIN);
      }
    }
  }
  return iosClass;
}

IOSClass *FetchArray(IOSClass *componentType) {
  static int key;
  IOSClass *iosClass = objc_getAssociatedObject(componentType, &key);
  if (!iosClass) {
    @synchronized (componentType) {
      iosClass = objc_getAssociatedObject(componentType, &key);
      if (!iosClass) {
        iosClass = AUTORELEASE([[IOSArrayClass alloc] initWithComponentType:componentType]);
        objc_setAssociatedObject(componentType, &key, iosClass, OBJC_ASSOCIATION_RETAIN);
      }
    }
  }
  return iosClass;
}

+ (void)load {
  // Check that app was linked with -force-load flag, as otherwise JRE support
  // will fail due to its categories not being loaded.
  if ([[NSObject class] instanceMethodSignatureForSelector:@selector(compareToWithId:)] == NULL) {
    [NSException raise:@"J2ObjCLinkError"
                format:@"Your project is not configured to load categories from the JRE "
     "emulation library. Did you forget the -force_load linker flag?"];
  }
}

+ (void)initialize {
  if (self == [IOSClass class]) {
    // Explicitly mapped classes are defined in Types.initializeTypeMap().
    // If types are added to that method (it's rare) they need to be added here.
    IOSClass_mappedClasses = [[NSDictionary alloc] initWithObjectsAndKeys:
         @"NSObject",  @"java.lang.Object",
         @"IOSClass",  @"java.lang.Class",
         @"NSNumber",  @"java.lang.Number",
         @"NSString",  @"java.lang.String",
         @"NSString",  @"java.lang.CharSequence",
         @"NSCopying", @"java.lang.Cloneable", nil];

    IOSClass_byteClass = [[IOSPrimitiveClass alloc] initWithName:@"byte" type:@"B"];
    IOSClass_charClass = [[IOSPrimitiveClass alloc] initWithName:@"char" type:@"C"];
    IOSClass_doubleClass = [[IOSPrimitiveClass alloc] initWithName:@"double" type:@"D"];
    IOSClass_floatClass = [[IOSPrimitiveClass alloc] initWithName:@"float" type:@"F"];
    IOSClass_intClass = [[IOSPrimitiveClass alloc] initWithName:@"int" type:@"I"];
    IOSClass_longClass = [[IOSPrimitiveClass alloc] initWithName:@"long" type:@"J"];
    IOSClass_shortClass = [[IOSPrimitiveClass alloc] initWithName:@"short" type:@"S"];
    IOSClass_booleanClass = [[IOSPrimitiveClass alloc] initWithName:@"boolean" type:@"Z"];
    IOSClass_voidClass = [[IOSPrimitiveClass alloc] initWithName:@"void" type:@"V"];

    IOSClass_objectClass = FetchClass([NSObject class]);
  }
}

@end
