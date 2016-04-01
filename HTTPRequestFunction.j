/*
 * Created by Martin Carlberg on April 23, 2015.
 * Copyright 2015, Martin Carlberg All rights reserved.
 */

@import <Foundation/Foundation.j>

@typedef IncomingMessage
@typedef ServerResponse

@protocol HTTPRequestFunction

- (id)initWithRequest:(IncomingMessage)aRequest response:(ServerResponse)aResponse data:(CPString)aBody databaseStore:(CPMutableDictionary)aDatabaseStore;

- (void)handleResponse;

@end
