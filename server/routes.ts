import { isAdmin, requireAdmin, requireUser } from './auth';
import { db } from './db';
import { readBody, Reply } from './http';
import { Router } from './router';
import * as cart from './services/cart';
import * as orders from './services/orders';
import * as products from './services/products';
import * as profiles from './services/profiles';
import * as settings from './services/settings';

/**
 * Every API endpoint. Request and response bodies use snake_case, matching the
 * database columns (and the Flutter models).
 */
export const router = new Router()
  // --- Public ---------------------------------------------------------------
  .get('/api/health', async () => ({
    status: 'ok',
    configured: {
      database: Boolean(process.env.DATABASE_URL),
      supabase: Boolean(process.env.SUPABASE_URL && process.env.SUPABASE_SECRET_KEY),
    },
  }))

  // --- Current user ---------------------------------------------------------
  .get('/api/me', async ({ request }) => profiles.getOrCreateProfile(await requireUser(request)))
  .patch('/api/me', async ({ request }) => {
    const user = await requireUser(request);
    return profiles.updateProfile(user, await readBody(request, profiles.updateProfileSchema));
  })

  // --- Cart -------------------------------------------------------------------
  .get('/api/cart', async ({ request }) => cart.getCart((await requireUser(request)).id))
  .post('/api/cart/items', async ({ request }) => {
    const user = await requireUser(request);
    return cart.addItem(user.id, await readBody(request, cart.addItemSchema));
  })
  .patch('/api/cart/items/:id', async ({ request, params }) => {
    const user = await requireUser(request);
    const { quantity } = await readBody(request, cart.updateItemSchema);
    return cart.updateItem(user.id, params.id, quantity);
  })
  .delete('/api/cart/items/:id', async ({ request, params }) =>
    cart.removeItem((await requireUser(request)).id, params.id),
  )

  // --- Checkout and customer orders -----------------------------------------
  .post('/api/checkout', async ({ request }) => {
    const user = await requireUser(request);
    const order = await orders.placeOrder(user, await readBody(request, orders.checkoutSchema));
    return new Reply({ order }, 201);
  })
  .get('/api/orders', async ({ request }) => orders.listOrders({ userId: (await requireUser(request)).id }))
  .get('/api/orders/:id', async ({ request, params }) => {
    const user = await requireUser(request);
    return orders.getOrderFor(user, params.id, await isAdmin(user.id));
  })
  .post('/api/orders/:id/cancel', async ({ request, params }) => {
    const user = await requireUser(request);
    return orders.cancelOrder(user, params.id, await isAdmin(user.id));
  })

  // --- Admin: orders --------------------------------------------------------
  .get('/api/admin/orders', async ({ request, query }) => {
    await requireAdmin(request);
    return orders.listOrders({ status: orders.parseStatus(query.get('status')) });
  })
  .patch('/api/admin/orders/:id', async ({ request, params }) => {
    const admin = await requireAdmin(request);
    return orders.adminUpdateOrder(admin, params.id, await readBody(request, orders.adminUpdateOrderSchema));
  })

  // --- Admin: catalog -------------------------------------------------------
  .get('/api/admin/categories', async ({ request }) => {
    await requireAdmin(request);
    return products.listCategories();
  })
  .get('/api/admin/products', async ({ request }) => {
    await requireAdmin(request);
    return products.listProducts();
  })
  .post('/api/admin/products', async ({ request }) => {
    await requireAdmin(request);
    const product = await products.saveProduct(null, await readBody(request, products.productSchema));
    return new Reply(product, 201);
  })
  .get('/api/admin/products/:id', async ({ request, params }) => {
    await requireAdmin(request);
    return products.getProduct(db(), params.id);
  })
  .put('/api/admin/products/:id', async ({ request, params }) => {
    await requireAdmin(request);
    return products.saveProduct(params.id, await readBody(request, products.productSchema));
  })
  .patch('/api/admin/products/:id', async ({ request, params }) => {
    await requireAdmin(request);
    return products.patchProduct(params.id, await readBody(request, products.patchProductSchema));
  })
  .delete('/api/admin/products/:id', async ({ request, params }) => {
    await requireAdmin(request);
    await products.deleteProduct(params.id);
    return new Reply(null, 204);
  })
  .post('/api/admin/products/:id/images/upload-url', async ({ request, params }) => {
    await requireAdmin(request);
    const { file_name } = await readBody(request, products.uploadUrlSchema);
    return products.createImageUpload(params.id, file_name);
  })
  .post('/api/admin/products/:id/images', async ({ request, params }) => {
    await requireAdmin(request);
    const product = await products.addImage(params.id, await readBody(request, products.addImageSchema));
    return new Reply(product, 201);
  })
  .delete('/api/admin/images/:id', async ({ request, params }) => {
    await requireAdmin(request);
    await products.deleteImage(params.id);
    return new Reply(null, 204);
  })

  // --- Admin: settings ------------------------------------------------------
  .put('/api/admin/settings', async ({ request }) => {
    await requireAdmin(request);
    return settings.updateSettings(await readBody(request, settings.settingsSchema));
  });
