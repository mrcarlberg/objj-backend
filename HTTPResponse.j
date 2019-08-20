/*
 * Created by Martin Carlberg on April 23, 2015.
 * Copyright 2015, Martin Carlberg All rights reserved.
 */

@import <LightObject/LOJSKeyedArchiver.j>

@protocol HTTPResponse 

/*!
    Returns the length of the data in bytes.
*/
- (CPUInteger)contentLength;

/*!
    Returns the data for the response.
*/
- (CPData)readDataOfLength:(CPUInteger)length;

/*!
    Returns true when all data is returned via the readDataOfLength method
*/
- (BOOL)isDone;

@optional

/*!
    Returns status code for response. Default is 200.
*/
- (CPInteger)status;

/*!
    Returns extra http headers.
*/
- (CPDictionary)httpHeaders;

/*!
    Not used yet! For future improvements!
*/
- (BOOL)isChunked;

@end

@implementation HTTPDataResponse : CPObject<HTTPResponse> {
    CPData data;
}

- (id)initWithData:(CPData)dataParam {
    if (self = [super init]) {
        data = dataParam;
    }
    return self;
}

- (CPUInteger)contentLength {
    return data ? [data length] : 0;
}

- (CPData)readDataOfLength:(NSUInteger)lengthParameter {
    if ((data ? [data length] : 0) <= lengthParameter) {
        return data;
    } else {
        [CPException raise:@"NotSupportedException" reason:@"Don't support getting data in chunks"];
    }
}

- (BOOL)isDone {
    // Maybe we should return YES only after the method 'readDataOfLength' is called.
    return YES;
}

- (CPDictionary)httpHeaders {
    return [CPDictionary dictionaryWithObjectsAndKeys:[CPString stringWithFormat:@"LOF Backend %@ (%@)", "<Version>", "<Port>"], @"Server", [self contentLength], "Content-Length"];
}

@end

@implementation JSONHTTPResponse : HTTPDataResponse

- (id)initWithJSObject:(JSObject)object {
    self = [super initWithData:object != nil ? [CPData dataWithJSONObject:object] : nil];
    if (self) {
        //[self setObject:object];
    }
    return self;
}

- (id)initWithObject:(id)object {
    self = [super initWithData:object != nil ? [CPData dataWithJSONObject:[LOJSKeyedArchiver archivedDataWithRootObject:object]] : nil];
    if (self) {
        //[self setObject:object];
    }
    return self;
}

- (CPDictionary)httpHeaders {
    var /*CPMutableDictionary*/ headers = [CPMutableDictionary dictionaryWithDictionary:[super httpHeaders]];

    [headers setObject:@"text/json; charset=utf-8" forKey:@"Content-Type"];

    return headers;
}

@end

@implementation BufferHTTPResponse : CPObject<HTTPResponse> {
        Buffer  bytes;
}

- (id)initWithBytes:(Buffer)someBytes {
    self = [super init];
    if (self) {
        bytes = someBytes;
    }
    return self;
}

- (CPUInteger)contentLength {
    return bytes ? bytes.length : 0;
}

- (CPData)readDataOfLength:(NSUInteger)lengthParameter {
    if ((bytes ? bytes.length : 0) <= lengthParameter) {
        return bytes;
    } else {
        [CPException raise:@"NotSupportedException" reason:@"Don't support getting data in chunks"];
    }
}

- (BOOL)isDone {
    // Maybe we should return YES only after the method 'readDataOfLength' is called.
    return YES;
}

- (CPDictionary)httpHeaders {
    return [CPDictionary dictionaryWithObjectsAndKeys:[CPString stringWithFormat:@"LOF Backend %@ (%@)", "<Version>", "<Port>"],
                                                                                 @"Server", [self contentLength], "Content-Length"];
}

@end

@implementation HtmlHTTPResponse : BufferHTTPResponse

/*- (id)initWithBytes:(Buffer)someBytes {
    self = [super initWithBytes:someBytes];
    if (self) {
    }
    return self;
}*/

- (CPDictionary)httpHeaders {
    var /*CPMutableDictionary*/ headers = [CPMutableDictionary dictionaryWithDictionary:[super httpHeaders]];

    [headers setObject:@"text/html; charset=utf-8" forKey:@"Content-Type"];

    return headers;
}

@end

@implementation UnauthorizedHTTPResponse : JSONHTTPResponse

- (id)initWithFunction:(id)aFunction {
    self = [super initWithObject:[CPDictionary dictionaryWithObject:[CPString stringWithFormat:@"Not authorized to use function %@", aFunction] forKey:@"error"]];
    if (self) {

    }
    return self;
}

- (CPInteger)status {
    return 403;
}

@end

@implementation ExceptionHTTPResponse : JSONHTTPResponse

- (id)initWithException:(CPException)exception {
    self = [super initWithObject:[CPDictionary dictionaryWithObject:[self exceptionInfo:exception] forKey:@"exception"]];
    if (self) {
        //self.exception = exception;
    }
    return self;
}

- (NSInteger)status {
    return 537;
}

- (CPDictionary)exceptionInfo:(CPException)exception {
    var /*CPMutableDictionary*/ exceptionInfo = [CPMutableDictionary dictionaryWithObject:[exception name] forKey:@"name"];

    if ([exception reason] != nil) {
        [exceptionInfo setObject:[exception reason] forKey:@"reason"];
    }
    if ([exception userInfo] != nil) {
        [exceptionInfo setObject:[exception userInfo] forKey:@"userInfo"];
    }
    [exceptionInfo setObject:exception.stack forKey:@"callStack"];

    return exceptionInfo;
}

@end

@implementation NotFoundHTTPResponse : HTTPDataResponse

- (NSInteger)status {
    return 404;
}

@end

