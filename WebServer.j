/*
 * Created by Martin Carlberg on January 27, 2016.
 * Copyright 2016, Martin Carlberg All rights reserved.
 */

@import <Foundation/CPObject.j>
@import "HTTPRequest.j"
@import "HTTPResponse.j"
@import "BackendFunctionRetrievemodel.j"
@import "BackendFunctionFetch.j"
@import "BackendFunctionModify.j"

@global require

var _sharedInstance = nil;

@implementation WebServer : CPObject {
    CPInteger port;
}

+ (WebServer) sharedInstance {
    if (!_sharedInstance) {
        _sharedInstance = [[WebServer alloc] init];
    }
    return _sharedInstance;
}

- (id)init {
    self = [super init];
    
    if (self) {
        port = 1337;
    }
    
    return self;
}

- (void)startWebServer {
    var http = require('http');

    var databaseStore = [CPMutableDictionary dictionary];

    var server = http.createServer(function (req, res) {
        // req is an http.IncomingMessage, which is a Readable Stream
        // res is an http.ServerResponse, which is a Writable Stream

        var method = req.method;

        var body = '';
        // we want to get the data as utf8 strings
        // If you don't set an encoding, then you'll get Buffer objects
        req.setEncoding('utf8');

        // Readable streams emit 'data' events once a listener is added
        req.on('data', function (chunk) {
            body += chunk;
        });

        // the end event tells you that you have entire body
        req.on('end', function () {
            switch (method) {
                case "GET":
                    [self handleHttpGETRequest:req completionHandler:function(httpResponse) {
                        if ([httpResponse respondsToSelector:@selector(status)]) {
                            res.statusCode = [httpResponse status];
                        }
                        if ([httpResponse respondsToSelector:@selector(httpHeaders)]) {
                            [[httpResponse httpHeaders] enumerateKeysAndObjectsUsingBlock:function(headerName, headerValue) {
                            res.setHeader(headerName, headerValue);
                            }];
                        }
                        var data = [[httpResponse readDataOfLength:[httpResponse contentLength]] rawString];
                        if (data != nil) {
                            res.write(data);
                        }
                        res.end();
                    }];
                    break;

                case "POST":
                    [self handleHttpPOSTRequest:req body:body completionHandler:function(httpResponse) {
                        if ([httpResponse respondsToSelector:@selector(status)]) {
                            res.statusCode = [httpResponse status];
                        }
                        if ([httpResponse respondsToSelector:@selector(httpHeaders)]) {
                            [[httpResponse httpHeaders] enumerateKeysAndObjectsUsingBlock:function(headerName, headerValue) {
                            res.setHeader(headerName, headerValue);
                            }];
                        }
                        var data = [[httpResponse readDataOfLength:[httpResponse contentLength]] rawString];
                        if (data != nil) {
                            res.write(data);
                        }
                        res.end();
                    }];
                    break;

                default:
                    res.statusCode = 400;
                    res.write('error: Unsupported method ' + method);
                    res.end();
            }
        });
    });

    server.listen(port);
    console.log("Webserver started on port " + port);
}
- (void)handleHttpGETRequest:(HTTPRequest)request completionHandler:(Function/*(CPObject<HTTPResponse>)*/)completionBlock {
    var /*CPString*/ path = request.url;
    var /*CPArray*/ pathComponents = [path pathComponents];
    var /*CPMutableArray*/ unqualifiedComponents = [pathComponents mutableCopy];
    var /*CPString*/ subpath;
    var /*CPString*/ sessionKey;
    var /*CPString*/ functionName;
    var /*Class*/ functionClass = nil;
    var /*CPDictionary*/ getQuery;
    var /*CPMutableDictionary*/ parameters;

    try {
        while (([unqualifiedComponents count] > 0) && ([[unqualifiedComponents lastObject] rangeOfString:@"="].location != CPNotFound)) {
            [unqualifiedComponents removeLastObject];
        }

        switch ([unqualifiedComponents count]) {
            case 0:
            case 1:
                // Path is invalid
                return completionBlock([[UnauthorizedHTTPResponse alloc] initWithFunction:@"-"]);

            case 2:
                // Path contains only a function name
                functionName = [unqualifiedComponents objectAtIndex:1];
                functionClass = [self functionClassForName:functionName];
                sessionKey = nil;
                subpath = @"";
                break;

            default:
                functionName = [unqualifiedComponents objectAtIndex:1];
                functionClass = [self functionClassForName:functionName];
                if (functionClass == nil) {
                    // Path contains a session key
                    sessionKey = [unqualifiedComponents objectAtIndex:1];
                    functionName = [unqualifiedComponents objectAtIndex:2];
                    functionClass = [self functionClassForName:functionName];
                    subpath = [[pathComponents subarrayWithRange:CPMakeRange(3, [pathComponents count] - 3)] componentsJoinedByString:@"/"];
                    if (functionClass == nil) {
                        // Path contains a session key, and an entity name
                        functionName = @"fetch";
                        functionClass = [BackendFunctionFetch class];
                        subpath = [[pathComponents subarrayWithRange:CPMakeRange(2, [pathComponents count] - 2)] componentsJoinedByString:@"/"];
                    }
                } else {
                    // Path contains a function name and a subpath
                    subpath = [[pathComponents subarrayWithRange:CPMakeRange(2, [pathComponents count] - 2)] componentsJoinedByString:@"/"];
                }
                break;
        }

        parameters = [[request allHeaderFields] mutableCopy];
        getQuery = [request parseGetParams];
        if (getQuery != nil) {
            parameters[@"getQuery"] = getQuery;
        }

        var /*CPObject <BackendFunction>*/ aFunction = [[functionClass alloc] initWithSubpath:subpath parameters:parameters];
        var parameterError = [aFunction parameterError];
        if (parameterError) {
            console.log("parameterError: " + [parameterError userInfo]);
        }

        if (!aFunction) {
            return completionBlock([[UnauthorizedHTTPResponse alloc] initWithFunction:functionName]);
        }

        if (/*Authority check*/true) {
            return [aFunction responseWithCompletionHandler:function(httpResponse) {
                return completionBlock(httpResponse);
            }];
        } else {
            return completionBlock([[UnauthorizedHTTPResponse alloc] initWithFunction:functionName]);
        }
    } catch (exception) {
        return completionBlock([[ExceptionHTTPResponse alloc] initWithException:exception]);
    }
}

- (CPObject<HTTPResponse>)handleHttpPOSTRequest:(HTTPRequest)request body:(CPString)data completionHandler:(Function/*(CPObject<HTTPResponse>)*/)completionBlock {
    var /*CPString*/ path = request.url;
    var /*CPData*/ body = request.body;
    var /*CPArray*/ pathComponents = [path pathComponents];
    var /*CPString*/ sessionKey;
    var /*CPString*/ functionName = [pathComponents count] > 0 ? [pathComponents objectAtIndex:1] : nil;
    var /*Class*/ functionClass = nil;
    var /*CPObject <BackendFunction>*/ aFunction;
//    var /*CPObject <HTTPResponse>*/ response;

    var jsonObject = [data objectFromJSON];
    var /*CPMutableDictionary*/ parameters = [CPMutableDictionary dictionaryWithJSObject:jsonObject recursively:YES];

    functionClass = [self functionClassForName:functionName];

//    if (!jsonObject) {
//        return [[ErrorHTTPResponse alloc] initWithError:postBodyJSONError session:nil];
//    }

    if ([pathComponents count] < 3) {
        aFunction = [[functionClass alloc] initWithSubpath:nil parameters:parameters];
    } else {
        aFunction = [[functionClass alloc] initWithSubpath:[CPString pathWithComponents:[pathComponents subarrayWithRange:CPMakeRange (2, [pathComponents count] - 2)]] parameters:parameters];
    }

    var parameterError = [aFunction parameterError];
    if (parameterError) {
        console.log("parameterError: " + [parameterError userInfo]);
    }

    if (/*Authority check*/true) {
        return [aFunction responseWithCompletionHandler:function(httpResponse) {
            return completionBlock(httpResponse);
        }];
    } else {
        return completionBlock([[UnauthorizedHTTPResponse alloc] initWithFunction:functionName]);
    }
}

- (Class)functionClassForName:(CPString)functionName {
    //if ([functionName rangeOfCharacterFromSet:[[CPCharacterSet letterCharacterSet] invertedSet]].location === CPNotFound)
    // As above function is missing in Cappuccino we split the string to check if string contains invalid characters
    if ([[functionName componentsSeparatedByCharactersInSet:[[CPCharacterSet letterCharacterSet] invertedSet]] count] === 1) {
        return CPClassFromString([CPString stringWithFormat:@"BackendFunction%@", [functionName capitalizedString]]);
    } else {
        return nil;
    }
}

@end