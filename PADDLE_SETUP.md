# Paddle Setup Guide for Tekla

Follow these steps to set up Tekla as a product on Paddle and connect it to your landing page.

## 1. Create the Tekla Product in Paddle

1. Log in to your Paddle dashboard at https://vendors.paddle.com
2. Go to **Catalog > Products**
3. Click **+ New Product**
4. Fill in:
   - **Name:** Tekla
   - **Description:** Virtual Keyboard for macOS with Swipe-to-Type
   - **Tax category:** Standard Digital Goods (or Software)
5. Save the product

## 2. Create a Price

1. On the product page, go to the **Prices** tab
2. Click **+ New Price**
3. Set your price (e.g., $9.99 USD one-time)
4. Choose **One-time** billing type
5. Save — you'll get a **Price ID** like `pri_01abc123...`
6. **Copy this Price ID** — you need it for the landing page

## 3. Get Your Client-Side Token

1. Go to **Developer Tools > Authentication** (or Settings > API Keys)
2. Find your **Client-side token** — it starts with `live_` (e.g., `live_56066aaf7cbe...`)
3. This is the same token you use for Ekual — it's account-wide, not per-product
4. **Copy this token**

## 4. Update the Landing Page

Open `docs/index.html` and replace the two placeholders:

### Replace the Paddle token (line with `Paddle.Initialize`):
```
BEFORE: token: "live_YOUR_PADDLE_TOKEN_HERE"
AFTER:  token: "live_56066aaf7cbe507b874f560dbcd"  (your actual token)
```

### Replace the Price ID (in `openCheckout` function):
```
BEFORE: priceId: "pri_YOUR_TEKLA_PRICE_ID"
AFTER:  priceId: "pri_01abc123..."  (your actual Tekla price ID)
```

## 5. Set Up the Success URL in Paddle

1. In Paddle dashboard, go to **Checkout > Settings** (or the product's checkout settings)
2. Set the **Success URL** to:
   ```
   https://corvusdevs.github.io/Tekla/success
   ```
3. This is the page that shows the unlock code after purchase

## 6. Enable GitHub Pages

1. Go to your Tekla GitHub repository settings
2. Navigate to **Settings > Pages**
3. Under **Source**, select **Deploy from a branch**
4. Choose the `main` branch and `/docs` folder
5. Save — your site will be at `https://corvusdevs.github.io/Tekla/`

## 7. Verify the Full Flow

1. Visit your landing page at `https://corvusdevs.github.io/Tekla/`
2. Click the Buy button — Paddle checkout overlay should appear
3. Complete a test purchase (use Paddle's sandbox/test mode first)
4. After payment, you should be redirected to the success page showing:
   - Unlock code: `TEKLA-UNLOCK-9V3R`
   - Download link to GitHub Releases

## Summary of Values to Fill In

| What | Where | Placeholder |
|------|-------|-------------|
| Paddle client token | `docs/index.html` line ~416 | `live_YOUR_PADDLE_TOKEN_HERE` |
| Tekla Price ID | `docs/index.html` line ~425 | `pri_YOUR_TEKLA_PRICE_ID` |
| Success URL (in Paddle) | Paddle dashboard | `https://corvusdevs.github.io/Tekla/success` |

## Notes

- The unlock code `TEKLA-UNLOCK-9V3R` is static and shown on the success page. You'll need to implement in-app validation to check this code.
- Your Paddle client token is the same one used for Ekual — it's shared across all products in your Paddle account.
- The Price ID is unique per product/price — you need a new one for Tekla.
- Remember to test in Paddle sandbox mode before going live.
