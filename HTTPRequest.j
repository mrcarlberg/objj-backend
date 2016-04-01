/*
 * Created by Martin Carlberg on April 23, 2015.
 * Copyright 2015, Martin Carlberg All rights reserved.
 */

@global require

@implementation XXHTTPRequest : CPObject

- (CPDictionary)allHeaderFields {
    return [CPDictionary dictionaryWithJSObject:self.headers];
}

- (CPDictionary)headersJSON {
    return self.headers;
}

- (CPDictionary)parseGetParams {
    var quaryJSDict = require('url').parse(self.url, true).query;
    return quaryJSDict ? [CPDictionary dictionaryWithJSObject:quaryJSDict] : [CPDictionary new];
}

@end

require('http').IncomingMessage.prototype.isa = XXHTTPRequest;
