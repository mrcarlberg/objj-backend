/*
 * Created by Martin Carlberg on January 3, 2016.
 * Copyright 2016, Martin Carlberg All rights reserved.
 */

@import <Foundation/CPString.j>
@import <Foundation/CPDictionary.j>
@import "BackendFunction.j"
@import <LightObject/CPManagedObjectModel+XCDataModel.j>

@global BackendModelPath
@global BackendOptions;
@global ValidatedDatabaseWithCompletionHandler
@global BackendDatabaseAdaptor

@implementation BackendFunctionRetrievemodel : CPObject<BackendFunction> {
    CPString               receivedData;
    Function               completionBlock;
    CPHTTPURLResponse      receivedResponse;
}

- (id)initWithSubpath:(CPString)subpath parameters:(CPDictionary)parameters {
    self = [super init];
    if (self) {
    }
    return self;
}

- (id)initWithSubpath:(CPString)subpath data:(CPData)data {
    [CPException raise:BackendUnknownHTTPMethodException format:@"Unknown method PUT"];
    return nil;
}

- (void)responseWithCompletionHandler:(Function/*(CPObject<HTTPResponse>)*/)aCompletionBlock {
    var path = [CPManagedObjectModel modelFilePathFromModelPath:BackendModelPath];
    var request = [CPURLRequest requestWithURL:path];

    if (BackendOptions.verbose) console.log("Receive model from real path: " + path);
    receivedData = nil;
    completionBlock = aCompletionBlock;
    [CPURLConnection connectionWithRequest:request delegate:self];
}

- (CPError)parameterError {
    return nil;
}


- (void)connection:(CPURLConnection)connection didReceiveResponse:(CPHTTPURLResponse)response {
    receivedResponse = response;
}

- (void)connection:(CPURLConnection)connection didReceiveData:(CPString)data {
    if (receivedData) {
        receivedData = [receivedData stringByAppendingString:data];
    } else {
        receivedData = data;
    }
}

- (void)connectionDidFinishLoading:(CPURLConnection)connection {
    var modelData = [CPData dataWithRawString:receivedData];

    receivedData = nil;
    if (!completionBlock) return;

    if (modelData == nil) {
        return completionBlock([[NotFoundHTTPResponse alloc] init]);
    } else {
        [BackendDatabaseAdaptor setModel:[CPManagedObjectModel objectModelFromXMLData:modelData]];
        ValidatedDatabaseWithCompletionHandler(function() {
            completionBlock([[HTTPDataResponse alloc] initWithData:modelData]);
        });
    }
}

- (void)connection:(CPURLConnection)connection didFailWithError:(id)error {
    CPLog.error(@"[" + [self className] + @" " + _cmd + @"] Error: " + error);
    if (completionBlock)
        completionBlock(nil);
    receivedData = nil;
}

@end
