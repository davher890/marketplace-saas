import { isAdmin, requireAdmin, requireUser } from './auth';
import { readBody, Reply } from './http';
import { Router } from './router';
import * as cart from './services/cart';
import * as catalog from './services/catalog';
import * as categories from './services/categories';
import * as orders from './services/orders';
import * as products from './services/products';
import * as profiles from './services/profiles';
import * as push from './services/push';
import * as sessions from './services/sessions';
import * as settings from './services/settings';
import { supabaseAdmin } from './supabase';

/**
 * Every API endpoint. Request and response bodies use snake_case, matching the
 * database columns (and the Flutter models).
 */
export const router = new Router()
  // --- Public ---------------------------------------------------------------
  .get('/api/health', async () => ({
    status: 'ok',
    configured: {
      supabase_url: Boolean(process.env.SUPABASE_URL),
      publishable_key: Boolean(process.env.SUPABASE_PUBLISHABLE_KEY),
      secret_key: Boolean(process.env.SUPABASE_SECRET_KEY),
    },
  }))
  // Storefront catalog: no session needed.
  .get('/api/categories', async () => catalog.listCategories())
  .get('/api/products', async ({ query }) =>
    catalog.listProducts({
      category: query.get('category'),
      featured: query.get('featured') === 'true',
    }),
  )
  .get('/api/products/:slug', async ({ params }) => catalog.getProductBySlug(params.slug))
  .get('/api/settings', async () => settings.getSettings())

  // --- Authentication (the app never calls Supabase Auth directly) ----------
  .post('/api/auth/signup', async ({ request }) =>
    new Reply(await sessions.signUp(await readBody(request, sessions.signUpSchema)), 201),
  )
  .post('/api/auth/login', async ({ request }) =>
    sessions.signIn(await readBody(request, sessions.signInSchema)),
  )
  .post('/api/auth/refresh', async ({ request }) =>
    sessions.refresh(await readBody(request, sessions.refreshSchema)),
  )
  .post('/api/auth/logout', async ({ request }) => sessions.signOut((await requireUser(request)).accessToken))
  .post('/api/auth/recover', async ({ request }) =>
    sessions.recover(await readBody(request, sessions.recoverSchema)),
  )
  .put('/api/auth/password', async ({ request }) => {
    const user = await requireUser(request);
    return sessions.changePassword(user, user.accessToken, await readBody(request, sessions.changePasswordSchema));
  })

  // --- Current user ---------------------------------------------------------
  .get('/api/me', async ({ request }) => profiles.getOrCreateProfile(await requireUser(request)))
  .patch('/api/me', async ({ request }) => {
    const user = await requireUser(request);
    return profiles.updateProfile(user, await readBody(request, profiles.updateProfileSchema));
  })
  .delete('/api/me', async ({ request }) => {
    const user = await requireUser(request);
    return profiles.deleteAccount(user, await readBody(request, profiles.deleteAccountSchema));
  })

  // --- Cart -------------------------------------------------------------------
  .get('/api/cart', async ({ request }) => cart.getCart(await requireUser(request)))
  .post('/api/cart/items', async ({ request }) => {
    const user = await requireUser(request);
    return cart.addItem(user, await readBody(request, cart.addItemSchema));
  })
  .patch('/api/cart/items/:id', async ({ request, params }) => {
    const user = await requireUser(request);
    const { quantity } = await readBody(request, cart.updateItemSchema);
    return cart.updateItem(user, params.id, quantity);
  })
  .delete('/api/cart/items/:id', async ({ request, params }) =>
    cart.removeItem(await requireUser(request), params.id),
  )

  // --- Checkout and customer orders -----------------------------------------
  .post('/api/checkout', async ({ request }) => {
    const user = await requireUser(request);
    const order = await orders.placeOrder(user, await readBody(request, orders.checkoutSchema));
    // Awaited because Vercel may freeze the function once it responds; it
    // never throws, so a failed notification doesn't fail the checkout.
    await push.notifyAdminsOfOrder(order);
    return new Reply({ order }, 201);
  })
  .get('/api/orders', async ({ request }) => {
    const user = await requireUser(request);
    return orders.listOrders(user.db, { userId: user.id });
  })
  .get('/api/orders/:id', async ({ request, params }) => {
    const user = await requireUser(request);
    return orders.getOrderFor(user, params.id, await isAdmin(user));
  })
  .post('/api/orders/:id/cancel', async ({ request, params }) => {
    const user = await requireUser(request);
    return orders.cancelOrder(user, params.id, await isAdmin(user));
  })

  // --- Admin: push notification devices -------------------------------------
  .post('/api/admin/devices', async ({ request }) => {
    const user = await requireAdmin(request);
    return push.registerDevice(user, await readBody(request, push.registerDeviceSchema));
  })

  // --- Admin: orders --------------------------------------------------------
  .get('/api/admin/orders', async ({ request, query }) => {
    await requireAdmin(request);
    return orders.listOrders(supabaseAdmin(), { status: orders.parseStatus(query.get('status')) });
  })
  .patch('/api/admin/orders/:id', async ({ request, params }) => {
    const admin = await requireAdmin(request);
    return orders.adminUpdateOrder(admin, params.id, await readBody(request, orders.adminUpdateOrderSchema));
  })

  // --- Admin: catalog -------------------------------------------------------
  .get('/api/admin/categories', async ({ request }) => {
    await requireAdmin(request);
    return categories.listCategories();
  })
  .post('/api/admin/categories', async ({ request }) => {
    await requireAdmin(request);
    const category = await categories.createCategory(await readBody(request, categories.categorySchema));
    return new Reply(category, 201);
  })
  .put('/api/admin/categories/:id', async ({ request, params }) => {
    await requireAdmin(request);
    return categories.updateCategory(params.id, await readBody(request, categories.categorySchema));
  })
  .patch('/api/admin/categories/:id', async ({ request, params }) => {
    await requireAdmin(request);
    const { is_active } = await readBody(request, categories.patchCategorySchema);
    return categories.setCategoryActive(params.id, is_active);
  })
  .post('/api/admin/categories/:id/move', async ({ request, params }) => {
    await requireAdmin(request);
    const { direction } = await readBody(request, categories.moveCategorySchema);
    return categories.moveCategory(params.id, direction);
  })
  .delete('/api/admin/categories/:id', async ({ request, params }) => {
    await requireAdmin(request);
    await categories.deleteCategory(params.id);
    return new Reply(null, 204);
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
    return products.getProduct(params.id);
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
