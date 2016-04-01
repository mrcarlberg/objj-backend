/*
 * Created by Martin Carlberg on January 27, 2016.
 * Copyright 2016, Martin Carlberg All rights reserved.
 */

@import <LightObject/CPEntityDescription.j>

@protocol LOExtendedEntity

- (CPUInteger)typeValueForAttributeName:(CPString)attributeName;
- (CPString)tableName;
- (CPAttributeDescription)primaryKeyAttribute;

@end

@implementation CPEntityDescription (LOExtendedEntity) <LOExtendedEntity> {
    JSObject typeValueCacheDict;
    CPAttributeDescription primaryKeyAttributeCache;
}

- (CPUInteger)typeValueForAttributeName:(CPString)attributeName {
    var theCache = typeValueCacheDict;

    if (!theCache)
        theCache = typeValueCacheDict = {};

    var cachedTypeValue = theCache[attributeName];

    if (cachedTypeValue === undefined) {
        cachedTypeValue = theCache[attributeName] = [[[self attributesByName] objectForKey:attributeName] typeValue]
    }

    return cachedTypeValue;
}

- (CPString)tableName {
    // Use table name from user info or the entity name
    return [[self userInfo] valueForKey:@"tableName"] || [self name];
}

- (CPAttributeDescription)primaryKeyAttribute {
    if (primaryKeyAttributeCache)
        return primaryKeyAttributeCache;

    var attributesByName = [self attributesByName];
    [attributesByName enumerateKeysAndObjectsUsingBlock:function(attributeName, attributeDescription) {
        if ([[attributeDescription userInfo] valueForKey:@"primaryKey"])
            return primaryKeyAttributeCache = attributeDescription;
    }];

    return primaryKeyAttributeCache = [attributesByName objectForKey:@"primaryKey"];
}

@end