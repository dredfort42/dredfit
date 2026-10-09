//
//  The process-wide owner of the one store — iOS's `@State private var store`
//  in `DredfitApp`. One store for the life of the process: two would each
//  write the file from their own memory.
//

package com.dredfit

import android.app.Application
import com.dredfit.store.AppStore

class DredfitApp : Application() {
    val store: AppStore by lazy {
        AppStore(storagePath = filesDir.toPath().resolve(AppStore.STATE_FILE_NAME))
    }
}
