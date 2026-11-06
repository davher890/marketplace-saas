package es.donagalleta.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createOrdersChannel()
    }

    /**
     * Channel for the "new order" pushes sent by the API (server/services/push.ts
     * uses its id). High importance so they pop up like a message.
     */
    private fun createOrdersChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            ORDERS_CHANNEL_ID,
            "Pedidos",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply { description = "Avisos de pedidos nuevos para administradores" }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    companion object {
        const val ORDERS_CHANNEL_ID = "orders"
    }
}
