# Learnings

Raw material for the write-up and the demo site. Short bullets; numbers only where measured.

## Phase 0: planning (2026-10-26)

- None of the three search APIs (`amazon_search`, `ebay_search`, `shein_search`) documents a GTIN/UPC/EAN field. Matching across stores has to work from titles, brands and prices, or pay for a product-detail call per item.
- The engine schemas are close but not identical: eBay has `is_sponsored` and price ranges, Amazon has `brand` but no sponsored flag in its docs example, Shein returns both local and USD prices. "Same schema across engines" is a goal with visible seams.
- eBay's robots.txt disallows search result pages (`/sch/`) for all crawlers.
- Trial: 100 requests, and at most 20% of plan credits per hour.

## Phase 1: SearchApi client and cache (done 2026-10-26; 1 credit spent)

- Minitest 6 no longer ships `Minitest::Mock` or `stub`. The client takes its HTTP transport as an argument instead, so tests pass a fake that records what would go over the wire.
- Mutation check: 11 deliberately planted bugs (cache key, credit cap, secret leak, retries, ledger) were each caught by at least one test.

### First live response: `ebay_search`, q="adidas samba og" (2026-10-26, one response, 60 items)

Observations from a single response, not conclusions. Phase 3 (the hand-captured HTML) is where to check them.

- Timing: SearchApi reported 2.57 s (2.39 s fetching eBay, 0.18 s parsing); the full round trip from Belgrade measured 3.37 s.
- `search_parameters` echoes the defaults it applied (`ebay_domain: ebay.com`, `country: US`, `delivery_country: US`) and never the API key. `request_url` is `ebay.com/sch/i.html?_nkw=…`, the path eBay's robots.txt disallows.
- Undocumented fields: `subtitle` on 60/60 items (size and brand, e.g. "US M 11 + more · adidas · adidas Samba"), `tag` on 1/60. eBay results have no `brand` field, so `subtitle` is the best brand source.
- Documented fields never present: `seller`, `is_sponsored`, `images`, `watching`, `items_sold`, `authenticity`, `is_free_return` (0/60 each). Some of that data is there, but only as raw strings in `extensions` ("123 sold", "14+ watchers", "Authenticity Guarantee").
- `is_sponsored` is absent rather than `false`, so "not sponsored" and "unknown" look the same.
- Price ranges: 4/60 items have no `extracted_price`, only `extracted_price_range: {from, to}` (e.g. "$84.00 to $128.00"). The unified record needs a min–max price.
- Condition: 39 "Brand New", 15 "Pre-Owned", 6 "New (Other)". A third of the listings aren't new, so matching must look at condition.
- Style codes (two letters plus four digits, e.g. `JH5633`) appear in 19/60 titles.

## Phase 2: unified record and matching (2026-10-26)

- Fetched 8 queries from Amazon and eBay: 14 calls in one run, no errors. Latency per call: Amazon 2.1–14.6 s, eBay 2.5–8.0 s (one sample each, from Belgrade).
- Shein failed twice on "adidas samba og": first our client timed out at 60 s, then SearchApi answered 503 "We could not retrieve results for this search. Please try again later." after 90.5 s. Both are in the ledger; whether they were billed is for the dashboard to say.
- Conversion: Amazon 448 listings became 441 products and 7 rejects (no price, only "more offers"); eBay 480 became 480 products. A test checks that every cached listing becomes a product or a reject with a reason, so nothing disappears silently.
- eBay: 215 of 480 listings (45%) are used. Condition has to be part of the record.
- eBay's misplaced shipping text holds across all 8 queries: 53 of 480 listings (11%).
- Amazon: `is_sponsored` is `true` on 64 of 448 listings and never `false`. `recent_sales` sometimes holds a badge instead ("Top Brand", "New on Amazon in past month").
- Brand: Amazon's field covers 392 of 441 products. eBay has no field: brands came from 357 titles and 6 subtitles, and 117 have none (mostly the generic queries, because our brand list only covers the queried brands).
- Style codes: 26% of eBay titles carry one (124/480) and 5% of Amazon titles (22/441). Sellers write codes; Amazon's catalogue titles mostly don't.
- Matching: the grouping uses 39 Amazon–eBay pairs (11 by style code, 28 by title). Precision: waiting for hand labels. First reading: style-code pairs look right, and some title pairs are clearly wrong (Dunk Low Twist vs Retro, a kids' "PS" 550 vs a men's, a leopard-print 501 vs the plain one).
- The variant problem, seen in real data: Amazon titles like "Mens Nike Dunk Low Retro" name no colorway. They are parent listings that cover many colours and sizes, so "the same product" is not well defined for them.
- No cross-store matches at all for "patagonia better sweater", "women's puffer jacket" or "crossbody bag".

## Bugs and surprises

Each entry: what happened, how we found it, the evidence, the fix.

1. **`Net::HTTP` silently retries a GET after a read timeout** (ours, prevented). Found by a test against a local TCP server: 2 requests arrived for 1 call. Fix: `max_retries: 0`. Test: `test_a_read_timeout_is_raised_without_retrying`.
   - Question for SearchApi: is a request billed if the client disconnects before the response? If so, this default makes every client-side timeout cost double.
2. **Cached JSON could only be read with a UTF-8 locale** (ours, real bug). Found on the first live call: with `LANG` unset, Ruby reads files as US-ASCII and `JSON.parse` failed on "’" (12 in the file) and "·" (101). Invisible in a normal terminal; it would break under cron, CI or Docker, which is where a scheduled check runs. The live path worked only because HTTP bodies are raw bytes. Fix: read cache files as UTF-8 explicitly. Test: `test_reads_utf8_even_when_the_process_locale_is_not_utf8`.
   - The same bug on the input side, found in review: with `LANG` unset, command-line arguments arrive labelled as raw bytes, so `bin/searchapi ebay_search q="women’s puffer jacket"` crashed while building the cache key. That happens before any request, so no credit was at risk. Fix: the CLI labels arguments as UTF-8 and rejects invalid ones by name. Tests run the CLI as a subprocess with no locale and live mode unset: `test/bin/searchapi_test.rb`.
   - Lesson: text crosses into a Ruby program at three edges here (files, HTTP bodies, command-line arguments), and each one needs an explicit encoding. Python has the same trap with `open()` using the locale, hence PEP 686.
3. **The linter silently skipped `bin/`** (tooling). Found by counting linted files: 15 instead of 16. Standard ignores `bin/*` by default. Fix: `.standard.yml` with `default_ignores: false`.
4. **Path traversal through the engine name** (ours, fixed). Found in review: `engine` goes straight into a file path, and the CLI takes it from the command line, so `bin/searchapi ../x q=y` pointed outside the cache folder. Fix: the cache accepts only `/\A[a-z0-9_]+\z/`, so every caller is protected, not just the CLI. Test: `test_an_engine_name_that_could_leave_the_cache_folder_is_rejected`.
   - Ruby trap: `^` and `$` match at every line break, not at the ends of the string, so `/^[a-z0-9_]+$/` accepts `"ebay_search\n../x"`. Checked by planting `^…$` in a copy: the newline case fails the suite.
5. **A shared constant could be changed in place** (ours, prevented). Ruby constants stop reassignment, not mutation. `Client::ENDPOINT` is a `URI` object, and a transport that set `.query` on it without copying would have changed where every later request goes. Fix: `ENDPOINT` is frozen. Test: `test_a_transport_that_mutates_the_endpoint_fails_loudly`. The first run of that test failed with `NameError` (a nested class can't see constants the outer test class gets through `include`), which is why you watch a test fail before trusting it.
6. **SearchApi's eBay `shipping` field sometimes holds other text** (theirs, observed once, unverified). In the first response, 7/60 items have "Buy It Now", "or Best Offer" or "Located in United States" in `shipping`. On auction listings the real cost ("+$14.95 delivery") sits in `extensions`. That looks like rows shifting by one when an auction card has an extra line. Also seen: "Free delivery" leaves `extracted_shipping` absent rather than `0.0`, and `buying_format` reads "0 bids · Time left1d 3h", with words glued together. To check against the HTML in Phase 3. Across all 8 queries: 53 of 480 listings (11%).
7. **Our timeout was shorter than SearchApi's own deadline** (ours, worked around). Shein: our client gave up at 60 s; on the next attempt SearchApi itself answered 503 at 90.5 s. With the shorter timeout we got a blind `Net::ReadTimeout` instead of their reason, and possibly paid for it. Fix: `SEARCHAPI_READ_TIMEOUT` for slow engines. Lesson: a client's timeout should be longer than the provider's.
   - SearchApi's Search History API (documented as free) would show whether a timed-out search finished on their side, but it answers 403 "You need an active subscription" on the trial.
8. **Grouping chained unrelated listings together** (ours, fixed). Joining every chain of matches (A~B and B~C puts A with C) merged 33 adidas listings into one group on real data. Fix: each eBay listing joins only its single best Amazon match. Test: `test_a_listing_joins_only_its_best_match_so_groups_do_not_chain`.
9. **A test broke when a column was added** (ours, test bug). The labels test edited the CSV by matching column positions as text; adding a link column shifted them. Fix: the test edits through the CSV parser, like a person in a spreadsheet would.
10. **The locale trap again, in a one-off command.** Reading the labels CSV without `encoding:` failed on "’". The library passes the encoding, so its tests were green. The fix belongs in the code that reads, not in remembering.
11. **Shein silently vanished from the search page** (ours, fixed). The catalog only reported missing engines among those with a converter; Shein has none, so it disappeared instead of showing as missing, which is "missing data looks like no results" again. Found by a web test. Fix: the catalog checks every engine in `config/queries.yml` and reports each missing one with its reason ("not cached", "no converter yet").
12. **Sinatra's ERB does not escape HTML by default** (prevented). Every title on the site comes from someone else's page. Fix: the erubi template engine with `escape_html: true`, so `<%= %>` escapes and raw output has to be asked for with `<%== %>`. Test: a `<script>` title renders as text.
13. **Every web test failed with "Host not permitted"** (a feature, not a bug). Sinatra 4.1 added host authorization against DNS rebinding: in development it only accepts requests addressed to localhost, `.test` names or IPs, and rack-test sends `Host: example.org`. Fix: the tests address `localhost`; the protection stays on. The site also binds to 127.0.0.1 only.
