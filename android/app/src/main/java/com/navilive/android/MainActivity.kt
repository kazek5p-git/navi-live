package com.navilive.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import com.navilive.android.ui.NaviLiveViewModel
import com.navilive.android.ui.navigation.NaviLiveNavHost
import com.navilive.android.ui.theme.NaviLiveTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            NaviLiveTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    val naviLiveViewModel: NaviLiveViewModel = viewModel()
                    NaviLiveNavHost(viewModel = naviLiveViewModel)
                }
            }
        }
    }
}
