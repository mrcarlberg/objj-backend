/*
 * Created by Martin Carlberg on January 3, 2016.
 * Copyright 2016, Martin Carlberg All rights reserved.
 */

@import <Foundation/CPString.j>
@import <Foundation/CPDictionary.j>

@protocol BackendFunction

- (id)initWithSubpath:(CPString)subpath parameters:(CPDictionary)parameters;
- (id)initWithSubpath:(CPString)subpath data:(id)data;
- (void)responseWithCompletionHandler:(Function/*(CPObject<HTTPResponse>)*/)completionBlock;
- (CPError)parameterError;

@end

BackendUnknownHTTPMethodException = @"BackendUnknownHTTPMethodException";
BackendFileNotFoundException = @"BackendFileNotFoundException";
