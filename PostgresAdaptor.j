/*
 * Created by Martin Carlberg on January 27, 2016.
 * Copyright 2016, Martin Carlberg All rights reserved.
 */

@import <Foundation/CPObject.j>
@import <LightObject/LightObject.j>

@global require
@global BackendOptions

var pg = require('pg');
var kCFNull = [CPNull null];

@protocol DatabaseAdaptor

- (id)initWithConnectionConfig:(JSObject)aConfig andModel:(CPManagedObjectModel)aModel;

- (void)fetchJSObjectsForEntityNamed:(CPString)entityName predicate:(CPPredicate)predicate completionHandler:(Function/*(CPArray)*/)completionBlock;
- (void)executeSqlFromArray:(CPArray)sqlArray completionHandler:(Function)completionBlock;

- (JSObject)sqlDictionaryForInsertRowWithEntityNamed:(CPString)entityName values:(CPDictionary)values;
- (JSObject)sqlDictionaryForUpdateRowWithEntityNamed:(CPString)entityName values:(CPDictionary)values;
- (JSObject)sqlDictionaryForDeleteRowWithEntityNamed:(CPString)entityName predicate:(CPPredicate)predicate;
- (void)fetchUniqueIdForEntityNamed:(CPString)entityName completionHandler:(Function/*(id)*/)completionBlock;

- (void)validatedDatabaseWithCompletionHandler:(Function/*(CPArray errors, CPArray correctionSql)*/)completionBlock;

@end

var PredicateTraversalOptionNone = 0;
var PredicateTraversalOptionIsLikePredicate = 1;
var PredicateTraversalOptionIsBitColumn = 2;

@implementation PostgresAdaptor : CPObject <DatabaseAdaptor> {
    JSObject                connectionConfig;
    CPManagedObjectModel    model @accessors;
    JSObject                fetchSqlCache;
}

/*!
    Init adaptor
    Config can be config object of url string
*/
- (id)initWithConnectionConfig:(JSObject)aConfig andModel:(CPManagedObjectModel)aModel {
    self = [super init];

    if (self) {
        connectionConfig = aConfig;
        model = aModel;
        fetchSqlCache = Object.create(null);
    }

    return self;
}

/*!
    Fetch objects from entity using predicate. Returns an array with Javascript objects.
 */
- (void)fetchJSObjectsForEntityNamed:(CPString)entityName predicate:(CPPredicate)predicate completionHandler:(Function/*(CPArray)*/)completionBlock {
    // The base sql without the WHERE clause is cached.
    var sql = fetchSqlCache[entityName];
    var entityDescription = [model entityWithName:entityName];

    if (sql == nil) {
        var attributeDictionary = [entityDescription attributesByName];

        sql = [self selectSQLForEntity:entityDescription attributeDictionary:attributeDictionary];
        fetchSqlCache[entityName] = sql;
    }

    [self fetchJSObjectForEntity:entityDescription selectSQL:sql predicate:predicate completionHandler:completionBlock];
}

/*!
    Fetch objects with attributes from entity using predicate. Returns an array with Javascript objects.
 */
- (void)fetchJSObjectsForEntityNamed:(CPString)entityName attributes:(CPArray)attributes predicate:(CPPredicate)predicate completionHandler:(Function/*(CPArray)*/)completionBlock {
    var entityDescription = [model entityWithName:entityName];
    var allAttributeDictionary = [entityDescription attributesByName];
    var attributeDictionary = [CPMutableDictionary dictionary];

    [attributes enumerateObjectsUsingBlock:function(attributeName) {
        var attributeDescription = [allAttributeDictionary objectForKey:attributeName];
        if (attributeDescription) {
            [attributeDictionary setObject:attributeDescription forKey:attributeName];
        } else {
            console.error("Attribute '" + attributeName + "' does not exist for entity '" + [entityDescription name] + "'");
        }
    }];

    var sql = [self selectSQLForEntity:entityDescription attributeDictionary:attributeDictionary];

    [self fetchJSObjectForEntity:entityDescription selectSQL:sql predicate:predicate completionHandler:completionBlock];
}

- (void)fetchJSObjectForEntity:(CPEntityDescription)entityDescription selectSQL:(CPString)sql predicate:(CPPredicate)predicate completionHandler:(Function/*(CPArray)*/)completionBlock {
    var parameters = [];
    if (predicate) {
        var whereSql = [self sqlForPredicate:predicate andEntity:entityDescription option:PredicateTraversalOptionNone parameters:parameters];
        sql += " WHERE " + whereSql;
    }

    if (BackendOptions.verbose) console.log("Sql: " + sql + (parameters ? ": " + parameters : ""));

    pg.connect(connectionConfig, function(err, client, done) {
        if(err) {
            return console.error('Could not connect to postgres', err);
        }
        client.query(sql, parameters, function(err, result) {
            if(err) {
              return console.error('Error running query', err);
            }

            done();
            if (completionBlock) completionBlock(result.rows);
        });
    });
}

- (CPString)selectSQLForEntity:(CPEntityDescription)entityDescription attributeDictionary:attributeDictionary {
    var sql = "SELECT ";
    var tableName = [entityDescription tableName];
    var first = YES;
    [attributeDictionary enumerateKeysAndObjectsUsingBlock:function(attributeName, attributeDescription) {
        if (![attributeDescription isTransient]) {
            if (first) first = NO;
            else sql += ", ";
            var columnName = [[attributeDescription userInfo] valueForKey:@"columnName"] || attributeName;
            sql += '"' + columnName + '"'
            if (columnName !== attributeName) {
                sql += ' AS "' + attributeName + '"';
            }
        }
    }];
    sql += ' FROM "' + tableName + '"';

    return sql;
}

- (CPString)sqlForPredicate:(CPPredicate)predicate andEntity:(CPEntityDescription)entityDescription option:(CPUInteger)anOption parameters:(CPArray)parameters {
    if ([predicate isKindOfClass:CPCompoundPredicate]) {
        var count = [[predicate subpredicates] count];
        if (count == 0) return nil;

        var compoundPredicateType = [predicate compoundPredicateType];
        var sql = "";
        var operator;
        switch (compoundPredicateType) {
            case CPNotPredicateType:
                sql = " NOT ";
                break;

            case CPAndPredicateType:
                operator = " AND ";
                break;

            case CPOrPredicateType:
                operator = " OR ";
                break;
        }

        [[predicate subpredicates] enumerateObjectsUsingBlock:function(p, index) {
            var nextSql = [self sqlForPredicate:p andEntity:entityDescription option:anOption parameters:parameters];
            if (nextSql) {
                if (index !== 0) sql += operator;
                sql += nextSql;
            }
        }];

        return sql;

    } else if ([predicate isKindOfClass:CPComparisonPredicate]) {
        var leftExpression = [predicate leftExpression];
        var rightExpression = [predicate rightExpression];
        var predicateOperatorType = [predicate predicateOperatorType];

        if (predicateOperatorType == CPLikePredicateOperatorType) {
            anOption = PredicateTraversalOptionIsLikePredicate;

        } else if (predicateOperatorType == CPBetweenPredicateOperatorType) {
            // To keep things simple, and in line with our traversal options,
            // convert rightExpression to aggregate expression with array of constant value expressions.
            if (!ConvertToAggregateExpressionWithArrayOfExpressionValues(@ref(rightExpression)))
                [CPException raise:@"PredicateException" format:@"invalid rhs of BETWEEN predicate: %@", predicate];

            var values = [rightExpression collection];
            if ([values count] != 2)
                [CPException raise:@"PredicateException" format:@"rhs of BETWEEN predicate must have 2 values: %@", predicate];

            var leftExpr = [self sqlForPredicate:leftExpression andEntity:entityDescription option:anOption parameters:parameters];
            var lowExpr = [self sqlForPredicate:values[0] andEntity:entityDescription option:anOption parameters:parameters];
            var highExpr = [self sqlForPredicate:values[1] andEntity:entityDescription option:anOption parameters:parameters];

            return " BETWEEN " + lowExpr + " AND " + highExpr;

        } else if (predicateOperatorType == CPInPredicateOperatorType) {
            if (!ConvertToAggregateExpressionWithArrayOfExpressionValues(@ref(rightExpression)))
                [CPException raise:@"PredicateException" format:@"invalid rhs of IN predicate: %@", predicate];

            /*if ([@[ @"BIT", @"Binary" ] containsObject:[anEntity dataTypeForKey:[leftExpression keyPath]]]) {
                anOption = PredicateTraversalOptionIsBitColumn;
            }*/

            var bExprs = [CPMutableArray array];
            var sql = [self sqlForPredicate:leftExpression andEntity:entityDescription option:anOption parameters:parameters];
            sql += " IN (";
            [[rightExpression collection] enumerateObjectsUsingBlock:function(expr, index) {
                if (index !== 0) sql += ", ";
                sql += [self sqlForPredicate:expr andEntity:entityDescription option:anOption parameters:parameters];
            }];
            return sql + ")";

        } else if (IsKeyPathOPConstantValueComparison(predicate, @ref(leftExpression), @ref(rightExpression))) {
            // deal with 'x = null' and 'x != null'
            if ([rightExpression constantValue] == nil) {
                if (predicateOperatorType == CPEqualToPredicateOperatorType) {
                    return [self sqlForPredicate:leftExpression andEntity:entityDescription option:anOption parameters:parameters] + " IS NULL";
                } else if (predicateOperatorType == CPNotEqualToPredicateOperatorType) {
                    return [self sqlForPredicate:leftExpression andEntity:entityDescription option:anOption parameters:parameters] + " IS NOT NULL";
                }
                // for other operator types, fall through and let the NSExpression handling section below throw on this nil constant value
            /*} else if ([@[ @"BIT", @"Binary" ] containsObject:[anEntity dataTypeForKey:[leftExpression keyPath]]]) {
                anOption = PredicateTraversalOptionIsBitColumn;*/
            }
        }

        var expression1 = [self sqlForPredicate:leftExpression andEntity:entityDescription option:anOption parameters:parameters];
        var expression2 = [self sqlForPredicate:rightExpression andEntity:entityDescription option:anOption parameters:parameters];
        switch (predicateOperatorType) {
            case CPEqualToPredicateOperatorType:
                return expression1 + " = " + expression2;
            case CPNotEqualToPredicateOperatorType:
                return expression1 + " <> " + expression2;
            case CPLessThanPredicateOperatorType:
                return expression1 + " < " + expression2;
            case CPLessThanOrEqualToPredicateOperatorType:
                return expression1 + " <= " + expression2;
            case CPGreaterThanPredicateOperatorType:
                return expression1 + " > " + expression2;
            case CPGreaterThanOrEqualToPredicateOperatorType:
                return expression1 + " >= " + expression2;
            case CPLikePredicateOperatorType:
                if (([predicate options] & CPCaseInsensitivePredicateOption) == 0) {
                    return expression1 + " like " + expression2;
                } else {
                    return expression1 + " caseinsensitivelike " + expression2;
                }
        }

        return [CPException raise:@"PredicateException" format:@"unsupported predicate operator type %lu", predicateOperatorType];

    } else if ([predicate isKindOfClass:CPExpression]) {
        var expression = predicate;
        var expressionType = [expression expressionType];
        if (expressionType == CPKeyPathExpressionType) {
            var attributeName = [expression keyPath];
            var attributeDescription = [[entityDescription attributesByName] objectForKey:attributeName];
            var columnName = [[attributeDescription userInfo] objectForKey:@"columnName"] || attributeName;

            return '"' + columnName + '"';
        } else if (expressionType == CPConstantValueExpressionType) {
            var value = [expression constantValue];
            if (value == nil || value == [CPNull null]) [CPException raise:@"PredicateException" format:@"unsupported constant value %@", value];
            if ([value isKindOfClass:CPString]) {
                if (anOption == PredicateTraversalOptionIsLikePredicate) {
                    value = [value stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
                    value = [value stringByReplacingOccurrencesOfString:@"%" withString:@"\\%"];
                    value = [value stringByReplacingOccurrencesOfString:@"_" withString:@"\\_"];
                    value = [value stringByReplacingOccurrencesOfString:@"*" withString:@"%"];
                } /*else if (anOption == GIFPredicateTraversalOptionIsBitColumn) {
                    NSData *d = [NSData dataWithHexadecimalString:value];
                    if (!d) [NSException raise:@"PredicateException" format:@"Can't coerce string to bit: '%@'", value];
                    value = d;
                }*/
            }
            [parameters addObject:value];
            return "$" + [parameters count];
        }
    }
    return nil;
}

var rollback = function(client, done) {
    client.query('ROLLBACK', function(err) {
        return done(err);
    });
};
var commit = function(client, done) {
    client.query('COMMIT', function(err) {
        return done(err);
    });
};

/*!
    Execute sql statments in array. Calls completion handler when finished. Array contains JS objects
    with two a attributes. 'sql' and 'parameters'.
 */
- (void)executeSqlFromArray:(CPArray)sqlArray completionHandler:(Function/*(id error)*/)completionBlock {
    pg.connect(connectionConfig, function(err, client, done) {
        if(err) {
            return console.error('could not connect to postgres', err);
        }

        client.query('BEGIN', function(err) {
            if(err) return rollback(client, done);

            // endCompletionBlock is NOT called if there is an error
            var f = function(aSqlArray, endCompletionBlock) {
                if ([aSqlArray count] > 0) {
                    var sqlDict = [aSqlArray objectAtIndex:0];
                    var complete = function(error, result) {
                        if(error) {
                            rollback(client, done);
                            if (completionBlock) completionBlock(error);
                            return console.error('error running query', JSON.stringify(sqlDict), error);
                        }
                        f(aSqlArray.slice(1), endCompletionBlock);
                    }
                    if (BackendOptions.verbose) console.log("Sql: " + sqlDict.sql + (sqlDict.parameters ? ": " + sqlDict.parameters : ""))
                    if (sqlDict.parameters)
                        client.query(sqlDict.sql, sqlDict.parameters, complete);
                    else
                        client.query(sqlDict.sql, complete);
                } else {
                    endCompletionBlock();
                }
            };
            f(sqlArray, function() {
                commit(client, function(error) {
                    done();
                    if (completionBlock) completionBlock(error);
                })
            });
        });
    });
}

- (JSObject)sqlDictionaryForInsertRowWithEntityNamed:(CPString)entityName values:(CPDictionary)values {
    var entityDescription = [model entityWithName:entityName];
    var tableName = [entityDescription tableName];
    var sql = 'INSERT INTO "' + tableName + '" (';
    var attributesByName = [entityDescription attributesByName];
    var parameters = [];
    var first = YES;
    [attributesByName enumerateKeysAndObjectsUsingBlock:function(attributeName, attributeDescription) {
        if (first) {
            first = NO;
        } else {
            sql += ", ";
        }
        sql += '"' + [attributeDescription columnName] + '"';
    }];

    sql += ') VALUES (';
    first = YES;

    [attributesByName enumerateKeysAndObjectsUsingBlock:function(attributeName, attributeDescription) {
        if (first) {
            first = NO;
        } else {
            sql += ", ";
        }
        var value = [values objectForKey:attributeName];
        [parameters addObject:value === kCFNull ? nil : value];
        sql += "$" + [parameters count];
    }];

    sql += ')';

    return parameters.length > 0 ? {sql:sql, parameters:parameters} : {sql:sql};
}

- (JSObject)sqlDictionaryForUpdateRowWithEntityNamed:(CPString)entityName values:(CPDictionary)values {
    var entityDescription = [model entityWithName:entityName];
    var tableName = [entityDescription tableName];
    var primaryKeyAttribute = [entityDescription primaryKeyAttribute];
    var sql = 'UPDATE "' + tableName + '" SET ';
    var attributesByName = [entityDescription attributesByName];
    var parameters = [];
    var first = YES;
    [attributesByName enumerateKeysAndObjectsUsingBlock:function(attributeName, attributeDescription) {
        if (attributeDescription !== primaryKeyAttribute) {
            if (first) {
                first = NO;
            } else {
                sql += ", ";
            }
            var value = [values objectForKey:attributeName];
            [parameters addObject:value === kCFNull ? nil : value];
            sql += '"' + [attributeDescription columnName] + '" = $' + [parameters count];
        }
    }];

    var primaryKeyKey = [primaryKeyAttribute name];
    var primaryKeyPredicate = [CPPredicate keyPath:primaryKeyKey equalsConstantValue:[values objectForKey:primaryKeyKey]];
    var whereSql = [self sqlForPredicate:primaryKeyPredicate andEntity:entityDescription option:PredicateTraversalOptionNone parameters:parameters];
    sql += " WHERE " + whereSql;

    return parameters.length > 0 ? {sql:sql, parameters:parameters} : {sql:sql};
}

/*!
    Creates sql dictionary with sql delete statement with provided predicate
 */
- (JSObject)sqlDictionaryForDeleteRowWithEntityNamed:(CPString)entityName predicate:(CPPredicate)predicate {
    var entityDescription = [model entityWithName:entityName];
    var tableName = [entityDescription tableName];
    var sql = 'DELETE FROM "' + tableName + '"';

    var parameters = [];
    if (predicate) {
        var whereSql = [self sqlForPredicate:predicate andEntity:entityDescription option:PredicateTraversalOptionNone parameters:parameters];
        sql += " WHERE " + whereSql;
    }

    return parameters.length > 0 ? {sql:sql, parameters:parameters} : {sql:sql};
}

- (void)fetchUniqueIdForEntityNamed:(CPString)entityName completionHandler:(Function/*(id)*/)completionBlock {
    pg.connect(connectionConfig, function(err, client, done) {
        if (err) {
            return console.error('could not connect to postgres', err);
        }
        client.query("select nextval('lof_global_primarykey_seq')", function(err, result) {
            if(err) {
              return console.error('error running query', err);
            }
            if (completionBlock) completionBlock(result.rows[0].nextval);
        });
    });
}

/*!
    This method will fetch meta data from database and validate it against the model
*/
- (void)validatedDatabaseWithCompletionHandler:(Function/*(CPArray errors, CPArray correctionSql)*/)completionBlock {
    pg.connect(connectionConfig, function(err, client, done) {
        if (err) {
            if(err.code === @"28P01") { // Invalid password
                var callee = arguments.callee;
                hidden("Database password: ", function(password) {
                    connectionConfig.password = password;
                    [self validatedDatabaseWithCompletionHandler:completionBlock];
                });
                return;
            } else {
                return console.error('could not connect to postgres', err);
            }
        }
        client.query('SELECT COUNT(*) FROM pg_class WHERE "relname" = $1 AND "relkind" = $2', ['lof_global_primarykey_seq', 'S'], function(err, result) {
            if(err) {
              return console.error('error running query', err);
            }

            var errors = [];
            var correctionSql = [];
            if (result.rows[0].count == 0) {
                [errors addObject:@"Sequence for primary keys is not in the database"];
                [correctionSql addObject:{sql: @'CREATE SEQUENCE "lof_global_primarykey_seq"'}];
            }

            client.query('SELECT table_schema, table_name, column_name, data_type, column_default, is_nullable, character_maximum_length FROM information_schema.columns WHERE table_schema = $1', ['public'], function(err, result) {
                if(err) {
                  return console.error('error running query', err);
                }
                // Create index over columns in table
                var tableIndex = {};
                [result.rows enumerateObjectsUsingBlock:function(columnRow) {
                    var columns = tableIndex[columnRow.table_name];
                    if (columns) {
                        columns.push(columnRow);
                    } else {
                        tableIndex[columnRow.table_name] = [columnRow];
                    }
                }];

                // Check all entities in the model. We don't care if there are tables in the database that is not in the model
                [[model entitiesByName] enumerateObjectsUsingBlock:function(entityName) {
                    var entityDescription = [model entityWithName:entityName];
                    if ([entityDescription isAbstract]) return;
                    var tableName = [entityDescription tableName];
                    var tableColumns = tableIndex[tableName];
                    if (tableColumns) {
                        var propertyDictionary = [entityDescription propertiesByName];
                        // Create a set of column names both from the CPAttributeDescriptions and the meta data table columns
                        var attributeColumnNameSet = [CPMutableSet new];
                        var attributeColumnNameDict = [CPMutableDictionary new];
                        [propertyDictionary enumerateKeysAndObjectsUsingBlock:function(propertyName, propertyDescription) {
                            if ([propertyDescription isKindOfClass:CPAttributeDescription] && ![propertyDescription isTransient]) {
                                var columnName = [[propertyDescription userInfo] valueForKey:@"columnName"] || propertyName;
                                [attributeColumnNameSet addObject:columnName];
                                [attributeColumnNameDict setObject:propertyDescription forKey:columnName];
                            }
                        }];
                        var columnNameSet = [CPSet new];
                        [tableColumns enumerateObjectsUsingBlock:function(columnRow) {
                            [columnNameSet addObject:columnRow.column_name];
                        }];
                        var missingColumnsInDatabaseSet = [attributeColumnNameSet mutableCopy];
                        [missingColumnsInDatabaseSet minusSet:columnNameSet];
                        [missingColumnsInDatabaseSet enumerateObjectsUsingBlock:function(columnName) {
                            [errors addObject:@"Column with column name '" + columnName + "' in table '" + tableName + "' is not in the database"];
                            var sql = @'ALTER TABLE "' + tableName + '" ADD COLUMN ' + [self sqlColumnNameAndTypeForAttribute:[attributeColumnNameDict objectForKey:columnName]];
                            [correctionSql addObject:{sql:sql}];
                        }];
                        [columnNameSet minusSet:attributeColumnNameSet];
                        [columnNameSet enumerateObjectsUsingBlock:function(columnName) {
                            [errors addObject:@"Column with column name '" + columnName + "' in table '" + tableName + "' is not in the model"];
                            // TODO: Here we should not drop the column in database as it might work and we will not care about the extra columns
                        }];
                        // Now we validate the type and size etc. of all attributes
                        [tableColumns enumerateObjectsUsingBlock:function(columnRow) {
                            var attributeDescription = [attributeColumnNameDict objectForKey:columnRow.column_name];
                            if (attributeDescription) {
                                [self validateColumnRow:columnRow withAttributeDescription:attributeDescription errors:errors correctionSql:correctionSql];
                            }
                        }];
                    } else {
                        [errors addObject:@"Entity with name '" + entityName + (entityName === tableName ? "" : "' and table name '" + tableName) + "' is missing in the database"];
                        // Table is missing. Create table in database
                        var sql = @'CREATE TABLE "' + tableName + '" (';
                        var propertyDictionary = [entityDescription propertiesByName];
                        var first = YES;
                        [propertyDictionary enumerateKeysAndObjectsUsingBlock:function(propertyName, propertyDescription) {
                            if ([propertyDescription isKindOfClass:CPAttributeDescription]) {
                                if (first)
                                    first = NO;
                                else
                                    sql += ', ';
                                sql += [self sqlColumnNameAndTypeForAttribute:propertyDescription];
                            }
                        }];
                        sql += ')';
                        [correctionSql addObject:{sql:sql}];
                    }
                }];
                done();
                if (completionBlock) completionBlock(errors, correctionSql);
            });
        });
    });
}

- (void)validateColumnRow:(JSObject)columnRow withAttributeDescription:(CPAttributeDescription)attributeDescription errors:(CPArray)errors correctionSql:(CPArray)correctionSql {
    var type = [attributeDescription typeValue];
    if ([self databaseTypeFromAttributeDescriptionValueType:type] !== columnRow.data_type) {
        [errors addObject:@"Attribute '" + [attributeDescription name] + @"' for entity '" + [[attributeDescription entity] name] + @"' has type '" + [attributeDescription typeName] + @"' in model but has type '" + columnRow.data_type + @"' in the database"];
        // TODO: Correct attribute with sql
    }
    if ([attributeDescription isOptional] !== (columnRow.is_nullable === 'YES')) {
        [errors addObject:@"Attribute '" + [attributeDescription name] + @"' for entity '" + [[attributeDescription entity] name] + @"' is " + ([attributeDescription isOptional] ? "" : "not ") + "optional in model but is " + (columnRow.is_nullable === 'YES' ? "" : "not ") + "nullable in the database"];
        // TODO: Correct attribute with sql
    }
}

- (CPString)sqlColumnNameAndTypeForAttribute:(CPAttributeDescription)propertyDescription {
    var type = [self databaseTypeFromAttributeDescriptionValueType:[propertyDescription typeValue]];
    var isPrimaryKey = [[propertyDescription userInfo] valueForKey:@"primaryKey"] || ([propertyDescription name] === @"primaryKey");
    var columnName = [[propertyDescription userInfo] valueForKey:@"columnName"] || [propertyDescription name];
    var sql = '"' + columnName + '" ' + type;
    if (![propertyDescription isOptional]) {
        sql += @" NOT NULL";
    }
    if (isPrimaryKey) {
        sql += @" PRIMARY KEY";
        if ([[@"integer", @"int", @"smallint", @"bigint"] containsObject:type]) {
            sql += @" DEFAULT nextval('lof_global_primarykey_seq')";
        }
    }

    return sql;
}

- (CPString)databaseTypeFromAttributeDescriptionValueType:(CPUInteger)typeValue {
    switch (typeValue) {
        case CPDIntegerAttributeType:
            return @"integer";
        case CPDInteger16AttributeType:
            return @"smallint";
        case CPDInteger32AttributeType:
            return @"integer";
        case CPDInteger64AttributeType:
            return @"bigint";
        case CPDDecimalAttributeType:
            return @"double precision";
        case CPDDoubleAttributeType:
            return @"double precision";
        case CPDFloatAttributeType:
            return @"real";
        case CPDStringAttributeType:
            return @"character varying";
        case CPDBooleanAttributeType:
            return @"boolean";
        case CPDDateAttributeType:
            return @"timestamp without time zone";
        case CPDBinaryDataAttributeType:
            return @"bit varying";
        case CPDTransformableAttributeType:
            return @"character varying";
        default:
            throw new Error(@"Model doesn't support attribute type: " + typeValue);
    }
}

- (void)setModel:(CPManagedObjectModel)aModel {
    model = aModel;
    // Clear the sql cache
    fetchSqlCache = Object.create(null);
}

@end


var IsKeyPathOPConstantValueComparison = function(/*CPComparisonPredicate*/ aPredicate, /*CPExpressionRef*/ left, /*CPExpressionRef*/ right) {
    var l = [aPredicate leftExpression];
    var r = [aPredicate rightExpression];
    var leftExpressionType = [l expressionType];
    if (leftExpressionType != CPKeyPathExpressionType) { var t = l; l = r; r = t; }
    if (leftExpressionType != CPKeyPathExpressionType) return NO;
    if ([r expressionType] != CPConstantValueExpressionType) return NO;
    if (left) @deref(left) = l;
    if (right) @deref(right) = r;
    return YES;
}

var ConvertToAggregateExpressionWithArrayOfExpressionValues = function(/*CPExpressionRef*/ anExpressionRef) {
    // The expression is either a constant value expression or an aggregate expression, with
    // 1. an array of values, or
    // 2. an array of constant value expressions of values, or
    // 3. a mix of the above.
    // convert it to a aggregate expression with an array containing constant value expressions.
    // Note: maybe allow for 'kp1 BETWEEN kp2' and 'kp1 IN kp2' predicates?
    if (!anExpressionRef) return NO;

    var anExpression = @deref(anExpressionRef);
    var type = [anExpression expressionType];
    if (type != CPConstantValueExpressionType && type != CPAggregateExpressionType) return NO;

    // -constantValue is same as -collection on aggregate expressions apparently in Cocoa. Not so in Cappuccino...
    var collection = type === CPConstantValueExpressionType ? [anExpression constantValue] : (type === CPAggregateExpressionType ? [anExpression collection] : nil);
    if (![collection isKindOfClass:CPArray]) return NO;

    var convertedValues = [CPMutableArray arrayWithCapacity:[collection count]];
    [collection enumerateObjectsUsingBlock:function(value) {
        // wrap constant value expressions
        if (![value isKindOfClass:CPExpression])
            value = [CPExpression expressionForConstantValue:value];

        if ([value expressionType] != CPConstantValueExpressionType)
            return NO;

        [convertedValues addObject:value];
    }];

    @deref(anExpressionRef) = [CPExpression expressionForAggregate:convertedValues];
    return YES;
}

var readline = require('readline');

function hidden(query, callback) {

    var rl = readline.createInterface({
        input: process.stdin,
        output: process.stdout
    });

    var rnd = 0;

    var stdin = process.openStdin();
    process.stdin.on("data", function(char) {
        char = char + "";
        switch (char) {
            case "\n":
            case "\r":
            case "\u0004":
                stdin.pause();
                break;
            default:
                rnd += Math.floor(Math.random() + 0.5);
                process.stdout.write("\033[2K\033[200D" + query + Array(rl.line.length+1+rnd).join("*"));
                break;
        }
    });

    rl.question(query, function(value) {
        rl.history = rl.history.slice(1);
        callback(value);
        rl.close();
    });
}
