import { errorResponse, json, preflight } from './_lib/http';
import { clientForRequest, HttpError, statusForPostgresError } from './_lib/supabase';

interface CheckoutBody {
  shippingName?: string;
  shippingPhone?: string | null;
  contactEmail?: string | null;
  customerNotes?: string | null;
  shippingAddress?: {
    line1?: string;
    line2?: string;
    city?: string;
    postal_code?: string;
    province?: string;
    country?: string;
  };
}

const MAX_TEXT = 500;

function optionalText(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  return trimmed ? trimmed.slice(0, MAX_TEXT) : null;
}

/**
 * POST /api/checkout
 * Turns the caller's cart into an order. Prices, stock and shipping are
 * computed inside the `place_order` SQL function, never trusted from the client.
 *
 * This is also the place to plug in payments later (e.g. create a PayPal or
 * Stripe payment for `order.total_cents` and return its approval URL).
 */
export async function POST(request: Request): Promise<Response> {
  try {
    const { supabase } = await clientForRequest(request);

    let body: CheckoutBody;
    try {
      body = (await request.json()) as CheckoutBody;
    } catch {
      throw new HttpError(400, 'Body must be valid JSON');
    }

    const address = body.shippingAddress ?? {};
    const { data: order, error } = await supabase.rpc('place_order', {
      p_shipping_name: optionalText(body.shippingName) ?? '',
      p_shipping_address: {
        line1: optionalText(address.line1) ?? '',
        line2: optionalText(address.line2) ?? '',
        city: optionalText(address.city) ?? '',
        postal_code: optionalText(address.postal_code) ?? '',
        province: optionalText(address.province) ?? '',
        country: optionalText(address.country) ?? 'ES',
      },
      p_shipping_phone: optionalText(body.shippingPhone),
      p_contact_email: optionalText(body.contactEmail),
      p_customer_notes: optionalText(body.customerNotes),
    });

    if (error) throw new HttpError(statusForPostgresError(error.code), error.message);

    // TODO: send confirmation emails (customer + shop) once a mail provider is chosen.
    return json(request, { order }, 201);
  } catch (error) {
    return errorResponse(request, error);
  }
}

export function OPTIONS(request: Request): Response {
  return preflight(request);
}
