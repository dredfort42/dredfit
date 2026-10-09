//
//  The one activity. Coming to the foreground is iOS's scene becoming
//  active: `activate()` runs the same sequence there and here.
//

package com.dredfit

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.ui.Modifier
import com.dredfit.store.activate
import com.dredfit.ui.today.TodayScreen

class MainActivity : ComponentActivity() {

    private val store get() = (application as DredfitApp).store

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            // Material 3 as a base only; Dredfit's own tokens arrive with ui/theme.
            MaterialTheme(colorScheme = if (isSystemInDarkTheme()) darkColorScheme() else lightColorScheme()) {
                Surface(Modifier.fillMaxSize()) {
                    TodayScreen(store, Modifier.safeDrawingPadding())
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        store.activate()
    }
}
