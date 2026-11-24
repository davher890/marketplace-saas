import 'package:dona_galleta/models/coupon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('discount comes off products and shipping, never below 0', () {
    const amount = Coupon(
      code: 'MENOS5',
      discountType: DiscountType.amount,
      amountCents: 500,
    );
    expect(amount.discountFor(2000, 600), 500);
    expect(amount.discountFor(300, 100), 400);

    const percent = Coupon(
      code: 'DESC10',
      discountType: DiscountType.percent,
      percent: 10,
    );
    expect(percent.discountFor(2000, 600), 260);
    expect(percent.discountFor(1995, 0), 200);

    const free = Coupon(code: 'ENVIO', discountType: DiscountType.freeShipping);
    expect(free.discountFor(2000, 600), 600);
    expect(free.discountFor(2000, 0), 0);
  });

  test('reads the admin list and writes what the API expects', () {
    final coupon = Coupon.fromJson({
      'id': 'c1',
      'code': 'NAVIDAD',
      'description': 'Campaña',
      'starts_on': '2026-12-01',
      'ends_on': '2026-12-31',
      'usage': 'once_per_user',
      'discount_type': 'free_shipping',
      'amount_cents': null,
      'percent': null,
      'is_active': true,
      'status': 'scheduled',
      'uses': 3,
    });
    expect(coupon.usage, CouponUsage.oncePerUser);
    expect(coupon.status, CouponStatus.scheduled);
    expect(coupon.uses, 3);
    expect(coupon.valueLabel, 'Envío gratis');
    expect(coupon.toJson(), {
      'code': 'NAVIDAD',
      'description': 'Campaña',
      'starts_on': '2026-12-01',
      'ends_on': '2026-12-31',
      'usage': 'once_per_user',
      'discount_type': 'free_shipping',
      'amount_cents': null,
      'percent': null,
      'is_active': true,
    });
  });
}
