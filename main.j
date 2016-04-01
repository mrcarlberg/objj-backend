/*
 * Created by Martin Carlberg on April 23, 2015.
 * Copyright 2015, Martin Carlberg All rights reserved.
 *
 * This is a webserver written in Objective-J running on Node.js.
 *
 * For more information on the Objective-J runtime check https://www.npmjs.com/package/objj-runtime
 *
 * Start the webserver from the command prompt with 'bin/objj main.j'
 *
 * From another command prompt json data can be stored with:
 * curl 127.0.0.1:1337/Name/42 -d '{"name": "martin"}'
 *
 * It can be retrived with:
 * curl 127.0.0.1:1337/Name/42
 *
 * The url uses a pattern with entity and identifier for storage. It looks like this:
 * curl 127.0.0.1:1337/<entity>/<identifier>
 */

@import <Foundation/Foundation.j>
@import "WebServer.j"
@import "PostgresAdaptor.j"
@import <LightObject/LightObject.j>

var path = require('path');
var url = require('url');

function help(status) {
    console.log("usage: " + path.basename(process.argv[1]) + " [OPTIONS] MODEL_FILE");
    console.log("OPTIONS:");
    console.log("        -d DATABASE_NAME        Name of the database. Defaults to model file name");
    console.log("        -u DATABASE_USERNAME    Username for the database.");
    console.log("        -p DATABASE_PASSWORD    Password for the database.");
    console.log("        -h DATABASE_HOSTNAME    Hostname for the database. Defaults to localhost");
    console.log("        -P DATABASE_PORT        Port for the database. Defaults to 5432");
    console.log("        -V                      Verify model against database.");
    console.log("        -A                      Alter database after model if verification fails.");
    console.log("        -v                      Verbose.");
    console.log("        -h | --help             Print usage.");
    process.exit(status);
}

BackendDatabaseAdaptor = nil;
BackendModelPath = nil;
BackendOptions = nil;

function main(args, namedArgs)
{
    var options = {databaseHost: "localhost"};
    var infiles = [];

    for (var i = 3; i < process.argv.length; ++i) {
        var arg = process.argv[i];
        if (arg == "-d") options.databaseName = process.argv[++i];
        else if (arg == "-u") options.databaseUsername = process.argv[++i];
        else if (arg == "-p") options.databasePassword = process.argv[++i];
        else if (arg == "-h") options.databaseHost = process.argv[++i];
        else if (arg == "-P") options.databasePort = process.argv[++i];
        else if (arg == "-V") options.verify = true;
        else if (arg == "-A") options.alter = true;
        else if (arg == "-v") options.verbose = true;
        else if (arg == "--help") help(0);
        else if (arg == "-h") help(0);
        else infiles.push([[CPURL URLWithString:arg] absoluteString]);
    }

    if (infiles.length !== 1) console.error(@"No model file"), help(1);
    if (options.databaseUsername == nil) console.error(@"No database username"), help(1);


    if ([infiles[0] hasPrefix:@"/"]) {
        BackendModelPath = [[CPURL URLWithString:@"file://" + infiles[0]] absoluteString];
    } else {
        BackendModelPath = [[CPURL URLWithString:[[@"file://" + path.dirname(process.mainModule.filename) stringByDeletingLastPathComponent] stringByAppendingPathComponent:infiles[0]]] absoluteString];
    }

    var model = [CPManagedObjectModel parseCoreDataModel:BackendModelPath/* completionHandler:function(model) {*/];
    var config = {
        user: options.databaseUsername,
        database: options.databaseName || [[BackendModelPath lastPathComponent] stringByDeletingPathExtension],
        host: options.databaseHost
    };

    if (model == nil) {
        console.error("Can't find model");
        process.exit(1);
    }
    if (options.databasePassword) config.password = options.databasePassword;
    if (options.databasePort) config.port = options.databasePort;

    var pgAdaptor = [[PostgresAdaptor alloc] initWithConnectionConfig:config andModel:model];

    BackendDatabaseAdaptor = pgAdaptor;
    BackendOptions = options;

    ValidatedDatabaseWithCompletionHandler(function() {
      [[WebServer sharedInstance] startWebServer];
    });
}

ValidatedDatabaseWithCompletionHandler = function(completionBlock)
{
    if (BackendOptions.verify) {
        [BackendDatabaseAdaptor validatedDatabaseWithCompletionHandler:function(errors, correctionSql) {
            if ([errors count] > 0) {
                if (BackendOptions.verbose) console.log("Validated database and found the following errors: ");
                [errors enumerateObjectsUsingBlock:function(error) {
                    console.warn(error);
                }];
                if (BackendOptions.alter) {
                    if (BackendOptions.verbose) console.log("Altering the database to correct errors: ");
                    [correctionSql enumerateObjectsUsingBlock:function(sqlDict) {
                        console.log(sqlDict.sql, sqlDict.parameters);
                    }];
                    [BackendDatabaseAdaptor executeSqlFromArray:correctionSql completionHandler:function(error) {
                        if (error != nil) console.error('Error running query:', JSON.stringify(sqlDict), err);
                        if (completionBlock) completionBlock();
                    }];
                } else {
                    if (completionBlock) completionBlock();
                }
            } else {
                if (BackendOptions.verbose) console.log("Validated database and found no errors");
                if (completionBlock) completionBlock();
            }
        }];
    } else {
        if (completionBlock) completionBlock();
    }
}
