/*
 * Created by Martin Carlberg on April 23, 2015.
 * Copyright 2015, Martin Carlberg All rights reserved.
 */

@implementation UnauthorizedHTTPResponder : CPObject <HTTPResonder>

- (id)initWithFunctionName:(CPString)functionName request:(HTTPRequest)request response:(HTTPResponse)response session:(id)userSession {
    self = [super init];
    if (self) {
        [NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"Not authorized to use function %@", functionName] forKey:@"error"] session:userSession];
    }
    return self;
}

- (NSInteger)status {
    return 403;
}

@end
