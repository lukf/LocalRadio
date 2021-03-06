//
//  IcecastController.m
//  LocalRadio
//
//  Created by Douglas Ward on 6/18/17.
//  Copyright © 2017 ArkPhone LLC. All rights reserved.
//

#import "IcecastController.h"
#import "AppDelegate.h"
#import "LocalRadioAppSettings.h"
#import "NSFileManager+DirectoryLocations.h"

@implementation IcecastController


// ================================================================

- (void)terminateTasks
{
    [self.icecastTask terminate];
}

//==================================================================================
//	startIcecastServer
//==================================================================================

- (void)startIcecastServer
{
    NSLog(@"Starting Icecast server");
    
    //[self stopIcecastServer];   // TEST
    
    int icecastProcessID = [self.appDelegate processIDForProcessName:@"icecast"];

    if (icecastProcessID == 0)
    {
        [self startIcecastTask];
    }
    else
    {
        /*
        NSAlert *alert = [[NSAlert alloc] init];
        
        [alert addButtonWithTitle:@"OK"];
        
        [alert setMessageText:@"Icecast is already running"];
        
        NSString * informativeText = [NSString stringWithFormat:@"An existing Icecast server process was found currently running on this Mac, so a new Icecast server process was not created.\n\nThe existing Icecast process can be inspected and terminated with Activity Monitor.app with Process ID (PID) %d.", icecastProcessID];
        
        [alert setInformativeText:informativeText];
        
        [alert setAlertStyle:NSWarningAlertStyle];

        if ([alert runModal] == NSAlertFirstButtonReturn)
        {
            // OK clicked
        }
        */

        
        NSNumber * icecastProcessIDNumber = [NSNumber numberWithInteger:icecastProcessID];
        
        [self performSelectorOnMainThread:@selector(poseIcecastProcessAlert:) withObject:icecastProcessIDNumber waitUntilDone:YES];
    }
}

//==================================================================================
//	poseIcecastProcessAlert
//==================================================================================

- (void)poseIcecastProcessAlert:(NSNumber *)icecastProcessIDNumber
{
    NSAlert *alert = [[NSAlert alloc] init];
    
    [alert addButtonWithTitle:@"OK"];
    
    [alert setMessageText:@"Icecast is already running"];
    
    NSString * informativeText = [NSString stringWithFormat:@"An existing Icecast server process was found currently running on this Mac, so a new Icecast server process was not created.\n\nThe existing Icecast process can be inspected and terminated with Activity Monitor.app with Process ID (PID) %@.", icecastProcessIDNumber];
    
    [alert setInformativeText:informativeText];
    
    [alert setAlertStyle:NSWarningAlertStyle];

    if ([alert runModal] == NSAlertFirstButtonReturn)
    {
        // OK clicked
    }
}

//==================================================================================
//	stopIcecastServer
//==================================================================================

- (void)stopIcecastServer
{
    NSLog(@"Stopping Icecast server");
    
    int icecastProcessID = [self.appDelegate processIDForProcessName:@"icecast"];

    if (icecastProcessID != 0)
    {
        NSError * fileError = NULL;
        NSString * icecastPidFilePath = [[NSFileManager defaultManager] applicationSupportDirectory];
        icecastPidFilePath = [icecastPidFilePath stringByAppendingPathComponent:@"icecast.pid"];

        NSString * icecastPidFileString = [NSString stringWithContentsOfFile:icecastPidFilePath encoding:NSUTF8StringEncoding error:&fileError];

        int icecastPidFileInt = icecastPidFileString.intValue;
        
        if (icecastProcessID == icecastPidFileInt)
        {
            // got double-confirmation of process ID of previous icecast launch by this app, so terminate it
            kill(icecastProcessID, SIGTERM);
        }
    }
}

// ================================================================

- (NSString *)icecastWebServerURLString
{
    NSString * hostString = [self.appDelegate localHostString];
    
    NSInteger portInteger = self.appDelegate.icecastServerPortTextField.integerValue;

    NSString * urlString = [NSString stringWithFormat:@"http://%@:%ld", hostString, portInteger];
    
    return urlString;
}

//==================================================================================
//	configureIcecast
//==================================================================================

- (void)configureIcecast
{
    NSString * applicationSupportDirectoryPath = [[NSFileManager defaultManager] applicationSupportDirectory];
    
    NSString * icecastPath = [applicationSupportDirectoryPath stringByAppendingPathComponent:@"icecast"];
    
    BOOL isDir;
    NSFileManager *fileManager= [NSFileManager defaultManager];
    
    if(![fileManager fileExistsAtPath:icecastPath isDirectory:&isDir])
    {
        if(![fileManager createDirectoryAtPath:icecastPath withIntermediateDirectories:YES attributes:nil error:NULL])
        {
            NSLog(@"Error: Create folder failed %@", icecastPath);
        }
    }
    
    NSString * icecastConfigTemplatePath = [NSBundle.mainBundle pathForResource:@"icecast" ofType:@"xml"];  // app's built-in master copy

    NSError * fileError = NULL;
    NSString * icecastXMLString = [NSString stringWithContentsOfFile:icecastConfigTemplatePath encoding:NSUTF8StringEncoding error:&fileError];

    NSError * xmlError = NULL;
    NSXMLDocument * xmlDocument = [[NSXMLDocument alloc] initWithXMLString:icecastXMLString options:0 error:&xmlError];

    NSXMLElement * rootElement = [xmlDocument rootElement];
    
    NSString * resourcePath = [NSBundle.mainBundle resourcePath];
    NSString * icecastWebPath = [resourcePath stringByAppendingPathComponent:@"icecast"];
    
   // change <hostname> to current IP address of this Mac
    NSString * hostnameQuery = @"hostname";
    NSError * error = NULL;
    NSArray * hostnameResultArray = [rootElement nodesForXPath:hostnameQuery error:&error];
    if (hostnameResultArray.count > 0)
    {
        NSXMLElement * hostnameElement = hostnameResultArray.firstObject;
        NSString * hostname = [self.appDelegate localHostString];
        [hostnameElement setStringValue:hostname];
    }

   // change <listen-socket><port>
    NSString * portQuery = @"listen-socket/port";
    //NSError * error = NULL;
    NSArray * portResultArray = [rootElement nodesForXPath:portQuery error:&error];
    if (portResultArray.count > 0)
    {
        NSXMLElement * portElement = portResultArray.firstObject;
        NSNumber * icecastServerPortNumber = [self.appDelegate.localRadioAppSettings integerForKey:@"IcecastServerPort"];
        NSString * portString = [NSString stringWithFormat:@"%ld", icecastServerPortNumber.integerValue];
        [portElement setStringValue:portString];
    }

   // change <basedir>/opt/local/share/icecast</basedir> containing admin, doc and web directories
    NSString * basedirQuery = @"paths/basedir";
    //NSError * error = NULL;
    NSArray * basedirResultArray = [rootElement nodesForXPath:basedirQuery error:&error];
    if (basedirResultArray.count > 0)
    {
        NSXMLElement * basedirElement = basedirResultArray.firstObject;
        [basedirElement setStringValue:icecastWebPath];
    }

    // change <logdir>/opt/local/var/log/icecast</logdir>
    NSString * logdirQuery = @"paths/logdir";
    NSArray * logdirResultArray = [rootElement nodesForXPath:logdirQuery error:&error];
    if (logdirResultArray.count > 0)
    {
        NSXMLElement * logdirElement = logdirResultArray.firstObject;
        [logdirElement setStringValue:icecastPath];
    }

    // change <webroot>/opt/local/share/icecast/web</webroot>
    NSString * webrootQuery = @"paths/webroot";
    NSArray * webrootResultArray = [rootElement nodesForXPath:webrootQuery error:&error];
    if (webrootResultArray.count > 0)
    {
        NSXMLElement * webrootElement = webrootResultArray.firstObject;
        NSString * webrootPath = [icecastWebPath stringByAppendingPathComponent:@"web"];
        [webrootElement setStringValue:webrootPath];
    }
    
    // change <adminroot>/opt/local/share/icecast/admin</adminroot>
    NSString * adminrootQuery = @"paths/adminroot";
    NSArray * adminrootResultArray = [rootElement nodesForXPath:adminrootQuery error:&error];
    if (adminrootResultArray.count > 0)
    {
        NSXMLElement * adminrootElement = adminrootResultArray.firstObject;
        NSString * adminrootPath = [icecastWebPath stringByAppendingPathComponent:@"admin"];
        [adminrootElement setStringValue:adminrootPath];
    }
    
    // <pidfile>/opt/local/share/icecast/icecast.pid</pidfile>
    NSString * pidfileQuery = @"paths/pidfile";
    NSArray * pidfileResultArray = [rootElement nodesForXPath:pidfileQuery error:&error];
    if (pidfileResultArray.count > 0)
    {
        NSXMLElement * pidfileElement = pidfileResultArray.firstObject;
        NSString * pidfilePath = [applicationSupportDirectoryPath stringByAppendingPathComponent:@"icecast.pid"];
        [pidfileElement setStringValue:pidfilePath];
    }
    
    NSString * xmlString = [xmlDocument XMLString];
    NSString * newIcecastConfigPath = [applicationSupportDirectoryPath stringByAppendingPathComponent:@"icecast.xml"];
    NSError * writeError = NULL;
    [xmlString writeToFile:newIcecastConfigPath atomically:NO encoding:NSUTF8StringEncoding error:&writeError];
}

//==================================================================================
//	startIcecastTask
//==================================================================================

- (void)startIcecastTask
{
    NSString * icecastPath = [NSBundle.mainBundle pathForAuxiliaryExecutable:@"icecast"];
    self.quotedIcecastPath = [NSString stringWithFormat:@"\"%@\"", icecastPath];

    NSString * applicationSupportDirectoryPath = [[NSFileManager defaultManager] applicationSupportDirectory];

    NSString * icecastConfigPath = [applicationSupportDirectoryPath stringByAppendingPathComponent:@"icecast.xml"];

    self.icecastTaskArgsArray = [NSArray arrayWithObjects:
            @"-c",
            icecastConfigPath,
            NULL];
    
    self.icecastTaskArgsString = [self.icecastTaskArgsArray componentsJoinedByString:@" "];
    
    NSLog(@"Launching icecast NSTask: \"%@\" -c \"%@\"", icecastPath, icecastConfigPath);
    
    self.icecastTask = [[NSTask alloc] init];
    self.icecastTask.launchPath = icecastPath;
    self.icecastTask.arguments = self.icecastTaskArgsArray;

    IcecastController * weakSelf = self;
    
    [self.icecastTask setTerminationHandler:^(NSTask* task)
    {           
        NSLog(@"enter IcecastController icecastTask terminationHandler, PID=%d", task.processIdentifier);

        if ([task terminationStatus] == 0)
        {
            NSLog(@"startIcecastTask - icecast terminationStatus 0");
        }
        else
        {
            NSLog(@"startIcecastTask - icecast terminationStatus %d", task.terminationStatus);
        }

        if ([(NSThread*)[NSThread currentThread] isMainThread] == NO)
        {
            //NSLog(@"IcecastController.startIcecastTask isMainThread = NO");
        }

        //self.appDelegate.statusIcecastServerTextField.stringValue = @"Not Running";

        [weakSelf.appDelegate.statusIcecastServerTextField performSelectorOnMainThread:@selector(setStringValue:) withObject:@"Not Running" waitUntilDone:NO];
        
        weakSelf.icecastTask = NULL;
        weakSelf.icecastTaskProcessID = 0;

        [weakSelf.appDelegate updateCurrentTasksText];
    }];
    
    [self.icecastTask launch];
    
    NSLog(@"Launched icecastTask, PID=%d", self.icecastTask.processIdentifier);
    
    self.icecastTaskProcessID = self.icecastTask.processIdentifier;

    if ([(NSThread*)[NSThread currentThread] isMainThread] == NO)
    {
        //NSLog(@"IcecastController.startIcecastTask isMainThread = NO");
    }

    //self.appDelegate.statusIcecastServerTextField.stringValue = @"Running";

    [self.appDelegate.statusIcecastServerTextField performSelectorOnMainThread:@selector(setStringValue:) withObject:@"Running" waitUntilDone:NO];

}

/*

Result of URL request to Icecast admin/stats converted to icecastStatusDictionary

Printing description of icecastStatusDictionary:
{
    admin = "icemaster@localhost";
    "client_connections" = 75;
    clients = 1;
    connections = 77;
    "file_connections" = 16;
    host = "192.168.10.8";
    icestats = "";
    "listener_connections" = 1;
    listeners = 0;
    location = Earth;
    "server_id" = "Icecast 2.4.2";
    "server_start" = "Mon, 12 Jun 2017 01:50:56 -0500";
    "server_start_iso8601" = "2017-06-12T01:50:56-0500";
    "source_client_connections" = 1;
    "source_relay_connections" = 0;
    "source_total_connections" = 1;
    sources = 1;
    "sources_list" =     (
                {
            "audio_info" = "bitrate=128;channels=2;samplerate=48000";
            bitrate = 128;
            channels = 2;
            genre = Live;
            "listener_peak" = 1;
            listeners = 0;
            listenurl = "http://192.168.10.8:17003/live";
            "max_listeners" = unlimited;
            public = 0;
            samplerate = 48000;
            "server_description" = "Unknown";
            "server_name" = "localradio";
            "server_type" = "audio/mpeg";
            "server_url" = "http://127.0.0.1:17003/live";
            "slow_listeners" = 0;
            source = "";
            "source_ip" = "127.0.0.1";
            "stream_start" = "Mon, 12 Jun 2017 01:52:39 -0500";
            "stream_start_iso8601" = "2017-06-12T01:52:39-0500";
            "total_bytes_read" = 86228992;
            "total_bytes_sent" = 224468;
            "user_agent" = "libshout/2.4.1";
        }
    );
    stats = 0;
    "stats_connections" = 0;
}
*/

//==================================================================================
//	icecastStatusDictionary
//==================================================================================

- (NSDictionary *)icecastStatusDictionary
{
    NSDictionary * resultDictionary = [NSDictionary dictionary];

    //NSNumber * httpServerPortNumber = [self.appDelegate.localRadioAppSettings integerForKey:@"HTTPServerPort"];
    //NSNumber * icecastServerModeNumber = [self.appDelegate.localRadioAppSettings integerForKey:@"IcecastServerMode"];
    //NSString * icecastServerHost = [self.appDelegate.localRadioAppSettings valueForKey:@"IcecastServerHost"];
    NSString * icecastServerSourcePassword = [self.appDelegate.localRadioAppSettings valueForKey:@"IcecastServerSourcePassword"];
    //NSString * icecastServerMountName = [self.appDelegate.localRadioAppSettings valueForKey:@"IcecastServerMountName"];
    //NSNumber * icecastServerPortNumber = [self.appDelegate.localRadioAppSettings integerForKey:@"IcecastServerPort"];

    NSString * icecastURL = [self icecastWebServerURLString];
    //NSString * icecastStatusURL = [icecastURL stringByAppendingPathComponent:@"status-json.xsl"];
    NSString * icecastStatusURLString = [icecastURL stringByAppendingPathComponent:@"admin/stats"];
    
    NSURL * icecastStatusURL = [NSURL URLWithString:icecastStatusURLString];

    NSError __block * icecastError = NULL;
    NSData __block * icecastResponseData;
    BOOL __block reqProcessed = false;
    NSURLResponse __block * icecastResponse;
    
    NSMutableURLRequest * icecastStatusURLRequest = [NSMutableURLRequest requestWithURL:icecastStatusURL];

    NSURLSession *session = [NSURLSession sharedSession];
    
    NSString *authStr = [NSString stringWithFormat:@"admin:%@", icecastServerSourcePassword];
    NSData *authData = [authStr dataUsingEncoding:NSUTF8StringEncoding];
    NSString *authValue = [NSString stringWithFormat: @"Basic %@",[authData base64EncodedStringWithOptions:0]];
    [icecastStatusURLRequest setValue:authValue forHTTPHeaderField:@"Authorization"];


    
    //[[session dataTaskWithURL:[NSURL URLWithString:icecastStatusURL]
    [[session dataTaskWithRequest:icecastStatusURLRequest
            completionHandler:^(NSData *data,
            NSURLResponse *response,
            NSError *error)
    {
        // handle response
        icecastResponse = response;
        icecastResponseData = data;
        icecastError = error;
        reqProcessed = true;
    }] resume];

    while (!reqProcessed) {
        [NSThread sleepForTimeInterval:0.1];
    }
    
    if (icecastResponseData != NULL)
    {
        NSString * xmlString = [[NSString alloc] initWithData:icecastResponseData encoding:NSUTF8StringEncoding];
        
        if (xmlString != NULL)
        {
            if (xmlString.length > 0)
            {
                NSDictionary * icecastStatusDictionary = [self parseIcecastStatusXML:xmlString];
                
                if (icecastStatusDictionary != NULL)
                {
                    resultDictionary = icecastStatusDictionary;
                }
            }
        }
    }
    
    return resultDictionary;
}

//==================================================================================
//	parseIcecastStatusXML
//==================================================================================

- (NSDictionary *)parseIcecastStatusXML:(NSString *)xmlString
{
    NSDictionary * icecastStatusDictionary = NULL;
    
    self.parserOutputDictionary = [NSMutableDictionary dictionary];
    
    NSData * xmlData = [xmlString dataUsingEncoding:NSUTF8StringEncoding];
    
    self.icecastStatusParser = [[NSXMLParser alloc] initWithData:xmlData];
    self.currentElementData = [NSMutableString string];
    self.currentSourceDictionary = [NSMutableDictionary dictionary];
   
    [self.icecastStatusParser setDelegate:self];
    [self.icecastStatusParser setShouldResolveExternalEntities:YES];
    
    BOOL success = [self.icecastStatusParser parse]; // return value not used
    
    if (success == YES)
    {
        icecastStatusDictionary = self.parserOutputDictionary;
        
        self.parserOutputDictionary = NULL;
        self.icecastStatusParser = NULL;
        self.currentElementData = NULL;
        self.currentSourceDictionary = NULL;
    }
    
    return icecastStatusDictionary;
}

//==================================================================================
//	parser:didStartElement:namespaceURI:qualifiedName:attributes
//==================================================================================

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
    [self addCurrentParserData];

     self.currentElementName = elementName;
    
     if ([elementName isEqualToString:@"source"] == YES)
     {
        self.inSourceElement = YES;
     }
}

//==================================================================================
//	parser:didEndElement:namespaceURI:qualifiedName:attributes
//==================================================================================

- (void)parser:(NSXMLParser *)parser didEndElement:(nonnull NSString *)elementName namespaceURI:(nullable NSString *)namespaceURI qualifiedName:(nullable NSString *)qName
{
    [self addCurrentParserData];

    if ([elementName isEqualToString:@"source"] == YES)
    {
        NSMutableArray * sourcesDictionary = [self.parserOutputDictionary objectForKey:@"sources_list"];
        if (sourcesDictionary == NULL)
        {
            sourcesDictionary = [NSMutableArray array];
            [self.parserOutputDictionary setObject:sourcesDictionary forKey:@"sources_list"];
        }
        
        [sourcesDictionary addObject:self.currentSourceDictionary];
        self.currentSourceDictionary = [NSMutableDictionary dictionary];
        self.inSourceElement = NO;
    }

    self.currentElementName = NULL;
}

//==================================================================================
//	parser:foundCharacters:
//==================================================================================

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string
{
    [self.currentElementData appendString:string];
}

//==================================================================================
//	parser:foundCharacters:
//==================================================================================

- (void)addCurrentParserData
{
    if (self.currentElementName != NULL)
    {
        if (self.currentElementData != NULL)
        {
            if (self.inSourceElement == YES)
            {
                [self.currentSourceDictionary setObject:self.currentElementData forKey:self.currentElementName];
            }
            else
            {
                [self.parserOutputDictionary setObject:self.currentElementData forKey:self.currentElementName];
            }
        }
    }

    self.currentElementData = [NSMutableString string];
}




@end
