//
//  BNCConfig.h
//  Branch-SDK
//
//  Created by Qinwei Gong on 10/6/14.
//  Copyright (c) 2014 Branch Metrics. All rights reserved.
//

#ifndef Branch_SDK_Config_h
#define Branch_SDK_Config_h

#define SDK_VERSION             @"0.12.16"
#define BNC_API_VERSION         @"v1"

#define BNC_PROD_ENV
//#define BNC_STAGE_ENV
//#define BNC_DEV_ENV


#if 1

    //  Ed Testing
    #define BNC_API_BASE_URL        @"https://esmith.api.beta.branch.io"
    #define BNC_LINK_URL            @"https://hhh8-esmith.branchbeta.link"

#elif defined(BNC_STAGE_ENV)

    #define BNC_API_BASE_URL        @"http://api.dev.branch.io"
    #define BNC_LINK_URL            @"https://bnc.lt"

#elif defined(BNC_DEV_ENV)

    #define BNC_API_BASE_URL        @"http://localhost:3001"
    #define BNC_LINK_URL            @"https://bnc.lt"

#else

    //  Production
    #define BNC_API_BASE_URL        @"https://api.branch.io"
    #define BNC_LINK_URL            @"https://bnc.lt"

#endif
#endif

