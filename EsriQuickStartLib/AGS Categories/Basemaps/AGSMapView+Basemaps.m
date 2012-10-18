//
//  AGSMapView+Basemaps.m
//  EsriQuickStartApp
//
//  Created by Nicholas Furness on 5/9/12.
//  Copyright (c) 2012 ESRI. All rights reserved.
//

#import "AGSMapView+Basemaps.h"
#import "EQSHelper.h"
#import "AGSLayer+Basemap.h"

#import <objc/runtime.h>

#define kEQSBasemapWebMapPayloadKey_LayersToKeep @"EQSLayersToKeepAcrossWebMapLoad"
#define kEQSBasemapWebMapPayloadKey_ExtentToKeep @"EQSExtentToKeepAcrossWebMapLoad"

#define kEQSBasemapTypeKey @"EQSBasemapTypeAsNumber"

#define kEQSNotification_BasemapDidChange_PortalItemKey @"PortalItem"
#define kEQSNotification_BasemapDidChange_BasemapsTypeKey @"BasemapType"

@interface AGSMapView()<AGSWebMapDelegate>
@end

@implementation AGSMapView (EQSBasemaps)

- (void) setBasemap:(EQSBasemapType)basemapType
{
    // Set up a static pointer to the current WebMap.
    static AGSWebMap *currentWebMap = nil;

    // Get the layers in the map which we didn't flag as Basemap Layers in the WebMap:DidLoad: handler below
    NSArray *currentLayersToKeep =
    [self.mapLayers filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id evaluatedObject,
                                                                                      NSDictionary *bindings) {
        AGSLayer *layer = evaluatedObject;
        return !layer.isEQSBasemapLayer;
    }]];
    
    // If the WebMap is not nil, this means it's been updated since initialization.
    // We must remove ourselves as the delegate before doing anything else.
    if (currentWebMap != nil)
    {
        currentWebMap.delegate = nil;
    }
    
    // Now get the WebMap we're switching to, and set ourselves as the delegate.
    currentWebMap = [EQSHelper getBasemapWebMap:basemapType];
    currentWebMap.delegate = self;
    
    objc_setAssociatedObject(currentWebMap, kEQSBasemapWebMapPayloadKey_LayersToKeep, currentLayersToKeep, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(currentWebMap, kEQSBasemapWebMapPayloadKey_ExtentToKeep, self.visibleArea.envelope, OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(currentWebMap, kEQSBasemapTypeKey, [NSNumber numberWithInt:basemapType], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    // And open it into the MapView.
    [currentWebMap openIntoMapView:self];
}

- (EQSBasemapType) getBasemapType
{
    NSNumber *basemapNum = objc_getAssociatedObject(self, kEQSBasemapTypeKey);
    
    // Ensure the helper library is being used properly.
    NSAssert(basemapNum != nil, @"You must call setBasemap (and the basemap must have loaded successfully) before trying to read the Basemap Type!");
    
    return (EQSBasemapType)basemapNum.intValue;
}

- (void)didOpenWebMap:(AGSWebMap *)webMap intoMapView:(AGSMapView *)mapView
{
    @try
    {
        // We've just loaded the webmap and have done nothing else.
        // The layers in here are all the layers we want to display as part of the basemap.
        for (AGSLayer *layer in self.mapLayers)
        {
            // So, flag them as basemap layers
            layer.isEQSBasemapLayer = YES;
        }
        
        // Read the envelope to restore the map to, and restore it.
        AGSEnvelope *envelopeToRestoreTo = objc_getAssociatedObject(webMap, kEQSBasemapWebMapPayloadKey_ExtentToKeep);
        if (envelopeToRestoreTo)
        {
            [mapView zoomToEnvelope:envelopeToRestoreTo animated:NO];
        }
        
        // Read the set of layers we need to add back on top of the basemap layers
        NSArray *layersToRestore = objc_getAssociatedObject(webMap, kEQSBasemapWebMapPayloadKey_LayersToKeep);
        if (layersToRestore)
        {
            // And add them, in order.
            for (AGSLayer *l in layersToRestore) {
                [self addMapLayer:l withName:l.name];
            }
        }
        
        NSNumber *basemapNum = objc_getAssociatedObject(webMap, kEQSBasemapTypeKey);
        objc_setAssociatedObject(self, kEQSBasemapTypeKey, basemapNum, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    @finally
    {
        // Lastly, release references to the objects we attached earlier. We don't need them any more.
        objc_setAssociatedObject(webMap, kEQSBasemapWebMapPayloadKey_LayersToKeep, nil, OBJC_ASSOCIATION_ASSIGN);
        objc_setAssociatedObject(webMap, kEQSBasemapWebMapPayloadKey_ExtentToKeep, nil, OBJC_ASSOCIATION_ASSIGN);
        objc_setAssociatedObject(webMap, kEQSBasemapTypeKey, nil, OBJC_ASSOCIATION_ASSIGN);
    }
    
    AGSPortalItem *pi = webMap.portalItem;
    [self postNewBasemapNotification:[self getBasemapType] forPortalItem:pi];
}

- (void)webMap:(AGSWebMap *)webMap didFailToLoadWithError:(NSError *)error
{
    @try
    {
        NSLog(@"Failed to load webmap: %@", error);
    }
    @finally
    {
        // Lastly, release references to the objects we attached earlier. We don't need them any more.
        objc_setAssociatedObject(webMap, kEQSBasemapWebMapPayloadKey_LayersToKeep, nil, OBJC_ASSOCIATION_ASSIGN);
        objc_setAssociatedObject(webMap, kEQSBasemapWebMapPayloadKey_ExtentToKeep, nil, OBJC_ASSOCIATION_ASSIGN);
    }
}

- (void)postNewBasemapNotification:(EQSBasemapType)basemapType forPortalItem:(AGSPortalItem *)portalItem
{
    NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];
    
    // Pass the basemap type with the notification
    [userInfo setObject:[NSNumber numberWithInt:basemapType]
                 forKey:kEQSNotification_BasemapDidChange_BasemapsTypeKey];

    // If we have a portal item, pass that back too.
    if (portalItem != nil)
    {
        [userInfo setObject:portalItem forKey:kEQSNotification_BasemapDidChange_PortalItemKey];
    }
    
    // Raise the notification
    [[NSNotificationCenter defaultCenter] postNotificationName:kEQSNotification_BasemapDidChange
                                                        object:self 
                                                      userInfo:userInfo];
}
@end

@implementation NSNotification (EQSBasemaps)
- (AGSPortalItem *) basemapPortalItem
{
    // Return the AGSPortalItem that represents this basemap type.
    return [self.userInfo objectForKey:kEQSNotification_BasemapDidChange_PortalItemKey];
}

- (EQSBasemapType) basemapType
{
    // And return the basemap type itself.
    NSNumber *basemapNum = [self.userInfo objectForKey:kEQSNotification_BasemapDidChange_BasemapsTypeKey];
    return (EQSBasemapType)basemapNum.intValue;
}
@end