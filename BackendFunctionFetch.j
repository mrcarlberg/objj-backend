/*
 * Created by Martin Carlberg on January 27, 2016.
 * Copyright 2016, Martin Carlberg All rights reserved.
 */

@import <Foundation/CPString.j>
@import <Foundation/CPDictionary.j>
@import "BackendFunction.j"
@import "CPEntityDescription+LOExtendedEntity.j"
@import "HTTPResponse.j"

@global BackendDatabaseAdaptor

var LightObjectBackendErrorDomainParameterError = -1;
var LightObjectBackendErrorDomainNoEntityError = -2;
var LightObjectBackendErrorDomainNoQualifierError = -3;
var LightObjectBackendErrorDomainInvalidTimestampError = -4;
var LightObjectBackendErrorDomainInvalidBooleanError = -5;
var LightObjectBackendErrorDomainUnknownTypeError = -6;

var LightObjectBackendErrorDomain = @"org.carlberg.lof";

@implementation BackendFunctionFetch : CPObject<BackendFunction> {
    CPError     parameterError @accessors(readonly);
    CPString    entityName;
    CPArray     qualifiers;
    CPString    operation;
    CPPredicate predicate;
}

- (id)initWithSubpath:(CPString)subpath parameters:(CPDictionary)parameters {
    self = [super init];
    if (self) {
        var armouredPredicateString = [parameters objectForKey:@"x-lo-advanced-qualifier"];
        var subQualifiers = [];

        var subpathComponents = [[subpath pathComponents] mutableCopy];
        if ([subpathComponents count] == 0) {
            parameterError = [CPError errorWithDomain:LightObjectBackendErrorDomain code:LightObjectBackendErrorDomainParameterError userInfo:@{@"CPLocalizedDescriptionKey": @"Cannot fetch without parameters."}];
            return self;
        }

        entityName = [subpathComponents objectAtIndex:0];
        [subpathComponents removeObjectAtIndex:0];

        while ([subpathComponents count] > 0) {
            var qualifierComponents = [[subpathComponents lastObject] componentsSeparatedByString:@"="];
            if ([qualifierComponents count] >= 2) {
                [subQualifiers insertObject:[CPDictionary dictionaryWithObject:[[qualifierComponents subarrayWithRange:CPMakeRange (1, [qualifierComponents count] - 1)] componentsJoinedByString:@"="] forKey:[qualifierComponents objectAtIndex:0]] atIndex:0];
                [subpathComponents removeLastObject];
            } else {
                break;
            }
        }
        qualifiers = subQualifiers;
        operation = [subpathComponents lastObject];

        if (armouredPredicateString) {
            predicate = [CPPredicate predicateFromLOJSONFormat:[[[CPData dataWithBase64:armouredPredicateString[0]] rawString] objectFromJSON]];
        } else if ([subQualifiers count] > 0) {
            var qualifierError = nil;
            predicate = [self predicateForQualifiers:subQualifiers entity:[[BackendDatabaseAdaptor model] entityWithName:entityName] error:@ref(qualifierError)];
            if (predicate == nil) {
                parameterError = qualifierError;
            }
        }
    }
    return self;
}

- (id)initWithSubpath:(CPString)subpath data:(CPData)data {
    [CPException raise:BackendUnknownHTTPMethodException format:@"Unknown method PUT"];
    return nil;
}

- (void)responseWithCompletionHandler:(Function/*(CPObject<HTTPResponse>)*/)completionBlock {
    if (operation === @"lazy") {
        // If we use lazy we want only an array with the primary keys
        var primaryKeyAttribute = [[[BackendDatabaseAdaptor model] entityWithName:entityName] primaryKeyAttribute];
        [BackendDatabaseAdaptor fetchJSObjectsForEntityNamed:entityName attributes:[[primaryKeyAttribute name]] predicate:predicate completionHandler:function(result) {
            if (completionBlock && result == nil) {
                return completionBlock([[NotFoundHTTPResponse alloc] init]);
            } else {
                var primaryKeyArray = [];
                var primaryKeyAttributeName = [primaryKeyAttribute name];
                [result enumerateObjectsUsingBlock:function(row) {
                    [primaryKeyArray addObject:row[primaryKeyAttributeName]];
                }];
                return completionBlock([[JSONHTTPResponse alloc] initWithJSObject:primaryKeyArray]);
            }
        }];
    } else {
        [BackendDatabaseAdaptor fetchJSObjectsForEntityNamed:entityName predicate:predicate completionHandler:function(result) {
            if (completionBlock && result == nil) {
                return completionBlock([[NotFoundHTTPResponse alloc] init]);
            } else {
                return completionBlock([[JSONHTTPResponse alloc] initWithJSObject:result]);
            }
        }];
    }
}

- (CPPredicate)predicateForQualifiers:(CPArray)someQualifiers entity:(CPEntityDescription)entity error:(CPErrorRef)error {
    if (!entity)
        return [CPError errorWithDomain:LightObjectBackendErrorDomain code:LightObjectBackendErrorDomainNoEntityError userInfo:@{CPLocalizedDescriptionKey: @"No such entity."}];

    var predicates = [CPMutableArray array];

    [someQualifiers enumerateObjectsUsingBlock:function(qualifier, index, stop) {
        var p = [self predicateForQualifier:qualifier entity:entity error:error];
        if (!p) return @deref(stop) = YES;
        [predicates addObject:p];
    }];

    if (@deref(error)) {
        return nil;
    } else {
        if ([predicates count] == 1) return [predicates objectAtIndex:0];
        if ([predicates count] > 1) {
            return [CPCompoundPredicate andPredicateWithSubpredicates:predicates];
        }
    }

    if (error) @deref(error) = [CPError errorWithDomain:LightObjectBackendErrorDomain code:LightObjectBackendErrorDomainNoQualifierError userInfo:@{CPLocalizedDescriptionKey: @"No qualifiers to transform."}];
    return nil;
}

- (CPPredicate)predicateForQualifier:(CPDictionary)qualifier entity:(CPEntityDescription<LOExtendedEntity>)entity error:(CPErrorRef)error {
    // Assumes entity != nil
    // Assumes qualifier is a dict with at least one item
    // Assumes qualifier key and value are strings
    // TODO: Validate qualifier so the type of an attribute corresponds to the value.
    //       For example: don't use a string if the type is an integer.
    var key = [[qualifier allKeys] objectAtIndex:0];
    var value = [qualifier objectForKey:key];
    var dataType = [entity typeValueForAttributeName:key];

    switch (dataType) {
        case CPDIntegerAttributeType:
        case CPDInteger16AttributeType:
        case CPDInteger32AttributeType:
        case CPDInteger64AttributeType:
            return [CPPredicate keyPath:key equalsConstantValue:[value integerValue]];

        case CPDDecimalAttributeType:
        case CPDDoubleAttributeType:
        case CPDFloatAttributeType:
            return [CPPredicate keyPath:key equalsConstantValue:[value doubleValue]];

        case CPDDateAttributeType:
            var d = value.parseISO8601Date();

            if (d == nil)
                return [self returnWithError:error forQualifierKey:key value:value code:LightObjectBackendErrorDomainInvalidTimestampError message:@"Invalid timestamp format."];

            return [CPPredicate keyPath:key equalsConstantValue:d];

        case CPDBooleanAttributeType:
            var b;
            if ([value isEqual:@"true"]) b = YES;
            else if ([value isEqual:@"false"]) b = NO;
            else return [self returnWithError:error forQualifierKey:key value:value code:LightObjectBackendErrorDomainInvalidBooleanError message:@"Invalid boolean format."];

            return [CPPredicate keyPath:key equalsConstantValue:b];

        case CPDStringAttributeType:
            return [CPPredicate keyPath:key equalsConstantValue:value];

        case CPDBinaryDataAttributeType:
            // TODO: We don't support binary data yet
    }

    return [self returnWithError:error forQualifierKey:key value:value code:LightObjectBackendErrorDomainUnknownTypeError message:@"Unknown data type " + [CPAttributeDescription typeNameForTypeValue:dataType]];
}

- (id)returnWithError:(CPErrorRef)error forQualifierKey:(CPString)key value:(CPString)value code:(CPInteger)code message:(CPString)message {
    if (error)
        @deref(error) = [CPError errorWithDomain:LightObjectBackendErrorDomain code:code userInfo:@{CPLocalizedDescriptionKey: message, @"key": key, @"value": value}];

    return nil;
}

@end


if (!String.prototype.parseISO8601Date) {
    String.prototype.parseISO8601Date = function() {
        var d = this.match(/^(\d{4})-?(\d{2})-?(\d{2})[T ](\d{2}):?(\d{2}):?(\d{2})(\.\d+)?(Z|(?:([+-])(\d{2}):?(\d{2})))$/i);
        if (!d) throw "ISODate, convert: Illegal format";
        return new Date(
                        Date.UTC(
                                 d[1], d[2]-1, d[3],
                                 d[4], d[5], d[6], d[7] || 0 % 1 * 1000 | 0
                                 ) + (
                                      d[8].toUpperCase() === "Z" ? 0 :
                                      (d[10]*3600 + d[11]*60) * (d[9] === "-" ? 1000 : -1000)
                                      )
                        );
    }
}