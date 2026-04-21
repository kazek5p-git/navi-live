package com.navilive.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import com.navilive.app.ui.NaviliveViewModel
import com.navilive.app.ui.navigation.NaviliveNavHost
import com.navilive.app.ui.theme.NaviliveTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            NaviliveTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    val naviliveViewModel: NaviliveViewModel = viewModel()
                    NaviliveNavHost(viewModel = naviliveViewModel)
                }
            }
        }
    }
}
