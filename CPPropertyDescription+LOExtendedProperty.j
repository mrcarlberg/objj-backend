/*
 * Created by Martin Carlberg on February 23, 2016.
 * Copyright 2016, Martin Carlberg All rights reserved.
 */

@import <Foundation/CPString.j>
@import <LightObject/CPRelationshipDescription.j>

@protocol LOExtendedAttribute

- (CPString)columnName;

@end

@protocol LOExtendedRelationship

- (CPString)foreignKeyAttributeName;

@end

@implementation CPRelationshipDescription (LOExtendedRelationship) <LOExtendedRelationship> 

- (CPString)foreignKeyAttributeName {
    // foreignKey name can be stored in the userInfo.
    var userInfo = [self userInfo];
    var foreignKeyName = [userInfo objectForKey:@"foreignKey"];

    if (foreignKeyName === nil) {
        // If no userInfo information exists on the relationship just assume it ends with 'ForeignKey'
        foreignKeyName = [self name] + @"ForeignKey";
    }

    return foreignKeyName;
}

@end


@implementation CPAttributeDescription (LOExtendedAttribute) <LOExtendedAttribute> 

- (CPString)columnName {
    return [[self userInfo] valueForKey:@"columnName"] || [self name];
}

@end
