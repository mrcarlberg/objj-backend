/*
 * Created by Martin Carlberg on February 21, 2016.
 * Copyright 2016, Martin Carlberg All rights reserved.
 */

@import <Foundation/CPString.j>
@import <Foundation/CPDictionary.j>
@import "BackendFunction.j"
@import "CPEntityDescription+LOExtendedEntity.j"
@import "CPPropertyDescription+LOExtendedProperty.j"
@import "HTTPResponse.j"

@global BackendDatabaseAdaptor

var LightObjectBackendErrorDomainParameterError = -1;
var LightObjectBackendErrorDomainNoEntityError = -2;
var LightObjectBackendErrorDomainNoQualifierError = -3;
var LightObjectBackendErrorDomainInvalidTimestampError = -4;
var LightObjectBackendErrorDomainInvalidBooleanError = -5;
var LightObjectBackendErrorDomainUnknownTypeError = -6;

var LightObjectBackendErrorDomain = @"org.carlberg.lof";

@implementation BackendFunctionModify : CPObject<BackendFunction> {
    CPError                 parameterError @accessors(readonly);
    CPMutableDictionary     inserts @accessors;
    CPMutableDictionary     updates @accessors;
    CPMutableDictionary     deletes @accessors;
    CPMutableDictionary     newIDs;
    CPMutableArray          modifiedRecords;
    CPMutableDictionary     modifiedRecordsIndexByPrimaryKey;
    CPMutableArray          sqls;
}

- (id)initWithSubpath:(CPString)subpath parameters:(CPDictionary)parameters {
    self = [super init];
    if (self) {
        inserts = [parameters objectForKey:@"inserts"];
        updates = [parameters objectForKey:@"updates"];
        deletes = [parameters objectForKey:@"deletes"];
    }
    return self;
}

- (id)initWithSubpath:(CPString)subpath data:(CPData)data {
    [CPException raise:BackendUnknownHTTPMethodException format:@"Unknown method PUT"];
    return nil;
}

- (void)responseWithCompletionHandler:(Function/*(CPObject<HTTPResponse>)*/)completionBlock {
    newIDs = [CPMutableDictionary dictionary];
    modifiedRecords = [CPMutableArray array];
    modifiedRecordsIndexByPrimaryKey = [CPMutableDictionary dictionary];
    sqls = [CPMutableArray array];

    var model = [BackendDatabaseAdaptor model];
    [deletes enumerateObjectsUsingBlock:function(anObject) {
        var entityName = [anObject objectForKey:@"_type"];
        var /*CPEntityDescription*/ entity = [model entityWithName:entityName];
        var primaryKeyAttribute = [entity primaryKeyAttribute];
        var primaryKeyKey = [primaryKeyAttribute name];
        var primaryKeyPredicate = [CPPredicate keyPath:primaryKeyKey equalsConstantValue:[anObject objectForKey:primaryKeyKey]];
        [sqls addObject:[BackendDatabaseAdaptor sqlDictionaryForDeleteRowWithEntityNamed:entityName predicate:primaryKeyPredicate]];
    }];

    var numberOfAsyncCalls = 0;
    [inserts enumerateObjectsUsingBlock:function(anObject) {
        var entityName = [anObject objectForKey:@"_type"];
        var /*CPEntityDescription*/ entity = [model entityWithName:entityName];
        var primaryKeyAttribute = [entity primaryKeyAttribute];
        var primaryKeyKey = [primaryKeyAttribute name];
        var values = [CPMutableDictionary dictionaryWithDictionary:anObject];
        var primaryKey = [anObject objectForKey:primaryKeyKey];
        [values setObject:YES forKey:@"_insert"];   // Make sure we know it should be an insert
        if (primaryKey == nil) {
            numberOfAsyncCalls++;
            [BackendDatabaseAdaptor fetchUniqueIdForEntityNamed:entityName completionHandler:function(fetchedPrimaryKey) {
                [newIDs setObject:fetchedPrimaryKey forKey:[anObject objectForKey:@"_tmpid"]];
                [values setObject:fetchedPrimaryKey forKey:primaryKeyKey];
                [values removeObjectForKey:@"_tmpid"];
                [modifiedRecordsIndexByPrimaryKey setObject:[modifiedRecords count] forKey:fetchedPrimaryKey];
                [modifiedRecords addObject:values];
                //if ([[[record entity] attributeNames] containsObject:@"creationTime"]) {
                //  [record setValue:modificationTime forKey:@"creationTime"];
                //}

                // Only do the next step if it is the last completion handler
                if (--numberOfAsyncCalls === 0) {
                    [self _createAndUpdateModifiedRecordsForUpdatesWithCompletionHandler:completionBlock];
                }
            }];
        }
    }];

    // If no async calls are made do the updates directly
    if (numberOfAsyncCalls === 0) {
        [self _createAndUpdateModifiedRecordsForUpdatesWithCompletionHandler:completionBlock];
    }
}

- (void)_createAndUpdateModifiedRecordsForUpdatesWithCompletionHandler:(Function/*(CPObject<HTTPResponse>)*/)completionBlock {
    var numberOfAsyncCalls = 0;
    var model = [BackendDatabaseAdaptor model];

    [updates enumerateObjectsUsingBlock:function(anObject) {
        var entityName = [anObject objectForKey:@"_type"];
        var /*CPEntityDescription*/ entity = [model entityWithName:entityName];
        var primaryKeyAttribute = [entity primaryKeyAttribute];
        var primaryKeyKey = [primaryKeyAttribute name];
        var values = [CPMutableDictionary dictionaryWithDictionary:anObject];
        var primaryKey = [anObject objectForKey:primaryKeyKey];
        var record;
        [values removeObjectForKey:@"_tmpid"];
        if (primaryKey != nil) {
            var recordIndex = [modifiedRecordsIndexByPrimaryKey objectForKey:primaryKey];
            if (recordIndex == nil) {
                var primaryKeyPredicate = [CPPredicate keyPath:primaryKeyKey equalsConstantValue:primaryKey];

                numberOfAsyncCalls++;
                [BackendDatabaseAdaptor fetchJSObjectsForEntityNamed:entityName predicate:primaryKeyPredicate completionHandler:function(result) {
                    // TODO: Take care of when the fetch returns nothing. The row can be deleted and we should return some kind of error
                    if ([result count] === 1) {
                        var fetchedRecord = [CPMutableDictionary dictionaryWithJSObject:result[0]];
                        [modifiedRecordsIndexByPrimaryKey setObject:[modifiedRecords count] forKey:primaryKey];
                        [modifiedRecords addObject:fetchedRecord];
                        [fetchedRecord addEntriesFromDictionary:values];
                        [self updateRecordsWithRelationsFromObject:anObject];
                    }

                    // Only do the next step if it is the last completion handler
                    if (--numberOfAsyncCalls === 0) {
                        [self _createSQLForModifiedRecordsWithCompletionHandler:completionBlock];
                    }
                }];
                // We do the rest in the completion handler
                return;
            } else {
                record = [modifiedRecords objectAtIndex:recordIndex];
            }
        } else {
            var recordIndex = [modifiedRecordsIndexByPrimaryKey objectForKey:[newIDs objectForKey:[anObject objectForKey:@"_tmpid"]]];
                record = [modifiedRecords objectAtIndex:recordIndex];
        }

        [record addEntriesFromDictionary:values];
        [self updateRecordsWithRelationsFromObject:anObject];
    }];

    // If no async calls are made do the sql directly
    if (numberOfAsyncCalls === 0) {
        [self _createSQLForModifiedRecordsWithCompletionHandler:completionBlock];
    }
}

- (void)_createSQLForModifiedRecordsWithCompletionHandler:(Function/*(CPObject<HTTPResponse>)*/)completionBlock {
    [modifiedRecords enumerateObjectsUsingBlock:function(record) {
//        if ([[[record entity] attributeNames] containsObject:@"modificationTime"]) {
//            [record setValue:modificationTime forKey:@"modificationTime"];
//        }

        var entityName = [record objectForKey:@"_type"];
        var isInsert = [record objectForKey:@"_insert"];

        if (isInsert) {
            [sqls addObject:[BackendDatabaseAdaptor sqlDictionaryForInsertRowWithEntityNamed:entityName values:record]];
        } else {
            [sqls addObject:[BackendDatabaseAdaptor sqlDictionaryForUpdateRowWithEntityNamed:entityName values:record]];
        }
    }];

    [BackendDatabaseAdaptor executeSqlFromArray:sqls completionHandler:function(error) {
        // TODO: Take care of errors
        if (completionBlock) {
            if ([newIDs count] > 0) {
                completionBlock([[JSONHTTPResponse alloc] initWithObject:[CPDictionary dictionaryWithObject:newIDs forKey:@"insertedIds"]]);
            } else {
                completionBlock([[JSONHTTPResponse alloc] initWithObject:nil]);
            }
        }
    }];
}

- (void)updateRecordsWithRelationsFromObject:(CPDictionary)object {
    var entityName = [object objectForKey:@"_type"];
    var model = [BackendDatabaseAdaptor model];
    var /*CPEntityDescription*/ entity = [model entityWithName:entityName];
    var /*CPDictionary*/ relationshipsByName = [entity relationshipsByName];
    
    [relationshipsByName enumerateKeysAndObjectsUsingBlock:function(relationshipName, relationshipDescription) {
        if ([relationshipDescription isToMany]) {
            [[[object objectForKey:relationshipName] objectForKey:@"inserts"] enumerateObjectsUsingBlock:function(aRelation) {
                // TODO: For now we just use 'primaryKey' as it works. Maybe we should use the destination entity primary key attribute? Or not?
                var key = [aRelation objectForKey:@"primaryKey"];
                if (key == nil) {
                    var tmpId = [aRelation objectForKey:@"_tmpid"];
                    if (tmpId == nil) return;
                    key = [newIDs objectForKey:tmpId];
                }

                var recordIndex = [modifiedRecordsIndexByPrimaryKey objectForKey:key];
                if (recordIndex != nil) {
                    var aRecord = [modifiedRecords objectAtIndex:recordIndex];
                    var destinationEntityName = [relationshipDescription destinationEntityName];
                    var destinationEntity = [model entityWithName:destinationEntityName]
                    var entityName = [object objectForKey:@"_type"];
                    var entity = [model entityWithName:entityName];
                    var primaryKeyAttribute = [entity primaryKeyAttribute];
                    var primaryKeyAttributeName = [primaryKeyAttribute name];
                    var objectPrimaryKey = [object objectForKey:primaryKeyAttributeName];
                    if (objectPrimaryKey == nil) {
                        var tmpId = [object objectForKey:@"_tmpid"];
                        if (objectPrimaryKey != nil) {
                            objectPrimaryKey = [newIDs objectForKey:tmpId];
                        }
                    }
                    if (objectPrimaryKey != nil) {
                        var inversePropertyName = [relationshipDescription inversePropertyName];
                        var inverseProperty = [[destinationEntity relationshipsByName] objectForKey:inversePropertyName];
                        var inverseForeignKeyAttributeName = [inverseProperty foreignKeyAttributeName];
                        [aRecord setObject:objectPrimaryKey forKey:inverseForeignKeyAttributeName];
                    }
                }
            }];
        }
    }];
}

@end
