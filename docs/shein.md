# Shein through SearchApi: what I measured

On 26 October 2026 I sent 11 searches to SearchApi's `shein_search` engine, with default parameters and only `q` (SearchApi applied `shein_domain: us.shein.com`). None returned listings. Two problems look like they sit on SearchApi's side; one was a bug of mine, now fixed.

| Outcome | Searches |
|---|---|
| HTTP 503 "We could not retrieve results for this search. Please try again later." after 90.4–90.9 s | 8 (one of them reproduced with plain curl) |
| HTTP 200 "Shein didn't return any results.", although the page SearchApi fetched has 20 products | 2 (both billed) |
| My client gave up after 60 s ([bug 27](../LEARNINGS.md), fixed) | 1 |

All 25 Amazon and eBay searches with the same key succeeded, in 2–15 s, two of them pairs within the same searches as Shein failures. status.searchapi.io, which shows the API as a whole rather than per engine, reported all systems operational.

## Every Shein search

Times are UTC, when the response arrived.

| Time | Query | Result | Took |
|---|---|---|---|
| 18:45:39 | adidas samba og | my client's `Net::ReadTimeout` (bug 27) | 60.1 s |
| 18:50:33 | adidas samba og | 503 (message not yet recorded by my client) | 90.5 s |
| 19:36:30 | adidas samba og | 200 "Shein didn't return any results." `search_d97LXP4moruBaXn9Mk03EOrl` | 11.8 s |
| 19:53:36 | nike dunk low panda | 503 | 90.8 s |
| 19:57:03 | women's puffer jacket | 503 | 90.7 s |
| 20:15:43 | dress | 503 | 90.9 s |
| 20:30:19 | nike air 1 | 200 "Shein didn't return any results." `search_8A9g6Ov07XHo3jKz34JlbW2m` | 75.3 s |
| 21:26:19 | new balance 550 | 503 (Shein only) | 90.8 s |
| 21:38:15 | hugo boss | 503 (Amazon 6.3 s and eBay 10.5 s in the same search) | 90.7 s |
| 22:24:37 | nike air max 90 | 503 (Amazon 3.3 s and eBay 4.4 s in the same search) | 90.9 s |
| 22:55:53 | dress | 503, sent with plain curl | 90.7 s |

## 1. A 503 after about 90 seconds

All eight 503s arrived between 90.46 and 90.90 s, for seven different queries, whether Shein was searched alone or together with Amazon and eBay. A spread of under half a second suggests a fixed deadline inside SearchApi rather than a slow Shein, though that is my inference.

Reproduced without any of my code:

```bash
curl -sS --max-time 180 -o body.json \
  -w "http %{http_code} | connect %{time_connect}s | first byte %{time_starttransfer}s\n" \
  -H "Authorization: Bearer $SEARCHAPI_API_KEY" \
  "https://www.searchapi.io/api/v1/search?engine=shein_search&q=dress"
```

Sent at 22:54:22 UTC: `HTTP/2 503` after 90.70 s. The connection opened in 0.12 s and the first byte arrived at 90.70 s, so the request was held until the deadline. Response header `x-request-id: f13193aa-8325-4bc0-835c-687ffad2bf3d`. The 503s were not billed, according to the Account API.

## 2. "No results" for pages with 20 products

| Search | Query | Fetching | Parsing | Products in the page SearchApi saved |
|---|---|---|---|---|
| `search_d97LXP4moruBaXn9Mk03EOrl` | adidas samba og | 10.93 s | 0.03 s | 20 Adidas shoes, 19 of them Sambas |
| `search_8A9g6Ov07XHo3jKz34JlbW2m` | nike air 1 | 74.47 s | 0.03 s | 20 Nike shoes: 9 Air Force 1, 10 Air Jordan 1, 1 Air Max 1 |

Each response links the HTML SearchApi fetched (`html_url`). In both pages the products sit in an embedded JSON array, `"products":[…]`, with `goods_id`, `goods_name`, `goods_sn`, `salePrice` and `retailPrice` (each with a `usdAmount`), `comment_num`, `comment_rank_average`, `goods_img` and `premiumFlagNew.brand_badge_name`. [`lib/cross_shop/shein_page.rb`](../lib/cross_shop/shein_page.rb) reads that array into the shape of SearchApi's `organic_results`; its tests are in [`test/cross_shop/shein_page_test.rb`](../test/cross_shop/shein_page_test.rb). Parsing took 0.03 s on pages of about 1.9 MB, which suggests the parser did not find the structure it expects; again my inference.

Both answers were billed: after 21 successful calls, these two included, the Account API reported 79 of 100 credits left. Failed calls were not billed.

## What I ruled out on my side

- **The request.** `engine=shein_search` with `q`, as the docs specify. SearchApi accepted it: the two answers carry search IDs and echo the parameters back.
- **The key.** The same key worked for Amazon and eBay in the same minutes. A bad key gets a quick 401, not a 503 after 90 s.
- **My timeouts.** Every 503 is a complete response with SearchApi's JSON message, received after about 90.5 s, while my client now waits 120 s. The one timeout on my side (60 s, bug 27) is listed separately.
- **Retries or duplicate requests.** `Net::HTTP` runs with `max_retries: 0`, and the ledger matches the Account API's billing call for call.
- **Parallel requests.** Shein also failed when searched alone (21:26:19).
- **Rate limits.** The account's hourly limit is 200,000 searches, and a rate limit would answer 429.
- **The query.** Seven different queries failed.
- **My client altogether.** The same 503, after the same 90.7 s, with plain curl.

## Data in this repo

- [`fixtures/searchapi/ledger.jsonl`](../fixtures/searchapi/ledger.jsonl): every live call, with status, SearchApi's message, search ID and duration. The curl call is marked `"client": "curl"`.
- [`fixtures/searchapi/responses/shein_search/`](../fixtures/searchapi/responses/shein_search/): the two "no results" answers as received.
- [`fixtures/searchapi/pages/shein_search/`](../fixtures/searchapi/pages/shein_search/): the two `html_url` pages, trimmed to their product list before publishing (`bin/trim-fixtures`). The parser gives identical output on the trimmed and the original pages.

## Open questions

1. Is the 90-second 503 on Shein a known issue?
2. Should an answer of "no results" be billed when the page fetched for it contains the products?
