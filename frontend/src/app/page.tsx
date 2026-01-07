import Link from "next/link";
import Image from "next/image";

export default function Home() {
  return (
    <div className="min-h-dvh bg-grid text-zinc-950">
      <header className="mx-auto flex w-full max-w-7xl items-center justify-between px-6 py-8">
        <div className="flex items-center gap-3">
          <div className="we-card rounded-2xl border-2 border-black bg-white p-3 shadow-[6px_6px_0_0_#000]">
            <Image src="/brand/logo.png" alt="welot" width={60} height={60} priority />
          </div>
          <div className="hidden sm:block">
            <div className="text-xs font-black">SAVE → WIN → WITHDRAW ANYTIME</div>
            <div className="text-xs font-semibold text-zinc-700">
              Weekly draw • prize is yield only • your deposit stays yours
            </div>
          </div>
        </div>

        <nav className="flex items-center gap-3">
          <Link
            href="/app"
            className="btn rounded-2xl border-2 border-black bg-zinc-950 px-4 py-2 text-sm font-black text-zinc-50 shadow-[4px_4px_0_0_#000]"
          >
            Enter App
          </Link>
        </nav>
      </header>

      <main className="mx-auto w-full max-w-7xl px-6 pb-24">
        <section className="relative grid gap-6 md:grid-cols-12">
          {/* Y2K shapes (decor only) */}
          <div aria-hidden className="pointer-events-none absolute -top-28 -left-56 z-0 hidden sm:block">
            <Image
              src="/shapes/y2k/shape-12.png"
              alt=""
              width={220}
              height={220}
              className="y2k-cyan we-floaty opacity-70 rotate-6"
            />
          </div>
          <div aria-hidden className="pointer-events-none absolute -top-32 -right-56 z-0 hidden md:block">
            <Image
              src="/shapes/y2k/shape-68.png"
              alt=""
              width={260}
              height={260}
              className="y2k-pink we-floaty opacity-60 -rotate-6"
            />
          </div>
          <div aria-hidden className="pointer-events-none absolute -bottom-40 left-1/2 z-0 hidden lg:block">
            <Image
              src="/shapes/y2k/shape-34.png"
              alt=""
              width={260}
              height={260}
              className="y2k-lime opacity-35 -translate-x-1/2 rotate-3"
            />
          </div>
          {/* Extra shapes tucked into padding/whitespace */}
          <div aria-hidden className="pointer-events-none absolute top-44 -left-60 z-0 hidden lg:block">
            <Image
              src="/shapes/y2k/shape-57.png"
              alt=""
              width={160}
              height={160}
              className="y2k-purple opacity-40 -rotate-12"
            />
          </div>
          <div aria-hidden className="pointer-events-none absolute bottom-0 -right-64 z-0 hidden lg:block">
            <Image
              src="/shapes/y2k/shape-90.png"
              alt=""
              width={170}
              height={170}
              className="y2k-cyan opacity-28 rotate-12"
            />
          </div>

          <div className="we-card relative z-10 rounded-3xl border-2 border-black bg-white p-8 shadow-[8px_8px_0_0_#000] md:col-span-8 xl:col-span-9">
            <div className="flex flex-wrap items-center gap-2">
              <div className="inline-flex items-center gap-2 rounded-2xl border-2 border-black bg-amber-100 px-3 py-2 text-sm font-black">
                <Image src="/icons/dice.svg" alt="" width={18} height={18} />
                weekly draw
              </div>
              <div className="inline-flex items-center gap-2 rounded-2xl border-2 border-black bg-pink-100 px-3 py-2 text-sm font-black">
                <Image src="/icons/ticket.svg" alt="" width={18} height={18} />
                tickets = deposits
              </div>
              <div className="inline-flex items-center gap-2 rounded-2xl border-2 border-black bg-lime-200 px-3 py-2 text-sm font-black">
                <Image src="/icons/moneybag.svg" alt="" width={18} height={18} />
                withdraw anytime
              </div>
            </div>

            <h1 className="font-display mag-underline mt-6 text-5xl tracking-tight md:text-6xl">
              Deposit.
              <br />
              Win the weekly prize.
              <br />
              Keep your deposit.
            </h1>

            <p className="mt-4 max-w-2xl text-base font-semibold text-zinc-700">
              welot is a no‑loss savings lottery. Your deposit stays withdrawable. The prize pool comes from generated yield.
            </p>

            <div className="mt-6 flex flex-col gap-3 sm:flex-row">
              <Link
                href="/app"
                className="btn inline-flex items-center justify-center rounded-2xl border-2 border-black bg-lime-200 px-5 py-3 text-base font-black shadow-[4px_4px_0_0_#000]"
              >
                Start
              </Link>
              <a
                href="#how-it-works"
                className="btn inline-flex items-center justify-center rounded-2xl border-2 border-black bg-white px-5 py-3 text-base font-black shadow-[4px_4px_0_0_#000]"
              >
                How it works
              </a>
            </div>
          </div>

          <div className="we-card relative z-10 rounded-3xl border-2 border-black bg-zinc-950 p-8 text-zinc-50 shadow-[8px_8px_0_0_#000] md:col-span-4 xl:col-span-3">
            <div className="flex items-center justify-between">
              <div>
                <div className="text-xs font-bold text-zinc-300">quick idea</div>
                <div className="font-display text-3xl we-wiggle">save + chance to win</div>
              </div>
              <div className="rounded-2xl border-2 border-black bg-white p-2">
                <Image src="/icons/sparkles.svg" alt="" width={22} height={22} />
              </div>
            </div>

            <div className="mt-5 rounded-2xl border-2 border-black bg-zinc-900 p-4">
              <div className="text-sm font-bold text-zinc-300">you can</div>
              <ul className="mt-3 space-y-2 text-sm font-semibold">
                <li className="flex items-center justify-between">
                  <span>deposit stablecoins</span>
                  <span className="rounded-xl border border-zinc-700 px-2 py-1 text-xs">tickets</span>
                </li>
                <li className="flex items-center justify-between">
                  <span>withdraw anytime</span>
                  <span className="rounded-xl border border-zinc-700 px-2 py-1 text-xs">no lock</span>
                </li>
                <li className="flex items-center justify-between">
                  <span>claim prizes</span>
                  <span className="rounded-xl border border-zinc-700 px-2 py-1 text-xs">if you win</span>
                </li>
              </ul>
            </div>

            <div className="mt-6 overflow-hidden rounded-2xl border-2 border-black bg-white">
              <img
                src="https://media4.giphy.com/media/v1.Y2lkPTc5MGI3NjExNDlveWxodnlzNXI0enJneWd5NWM2Y3NiYjZ4dnV2Y3hjN29rd3B6OCZlcD12MV9pbnRlcm5hbF9naWZfYnlfaWQmY3Q9Zw/lPJhsNXQrPfcZcFHsM/giphy.gif"
                alt="brand animation"
                loading="lazy"
                className="h-40 w-full object-cover"
              />
            </div>
            <p className="mt-3 text-xs font-semibold text-zinc-300">Coming soon on mainnet.</p>
          </div>
        </section>

        <section id="how-it-works" className="mt-10 scroll-mt-20">
          <h2 className="font-display mag-underline text-4xl tracking-tight">How it works</h2>
          <div className="relative mt-4 grid gap-4 md:grid-cols-3">
            <div aria-hidden className="pointer-events-none absolute -top-24 -right-60 z-0 hidden md:block">
              <Image
                src="/shapes/y2k/shape-57.png"
                alt=""
                width={180}
                height={180}
                className="y2k-purple we-floaty opacity-45 rotate-12"
              />
            </div>
            <div className="we-card relative z-10 rounded-3xl border-2 border-black bg-amber-100 p-6 shadow-[6px_6px_0_0_#000]">
              <div className="text-sm font-black">1) deposit</div>
              <div className="mt-2 text-base font-semibold text-zinc-800">
                Deposit stablecoins. You can withdraw whenever you want.
              </div>
            </div>
            <div className="we-card relative z-10 rounded-3xl border-2 border-black bg-pink-100 p-6 shadow-[6px_6px_0_0_#000]">
              <div className="text-sm font-black">2) tickets</div>
              <div className="mt-2 text-base font-semibold text-zinc-800">
                Tickets come from deposits. More deposited = more chances.
              </div>
            </div>
            <div className="we-card relative z-10 rounded-3xl border-2 border-black bg-lime-200 p-6 shadow-[6px_6px_0_0_#000]">
              <div className="text-sm font-black">3) weekly prize</div>
              <div className="mt-2 text-base font-semibold text-zinc-800">
                Each week the prize pool is awarded. Your deposit stays yours.
              </div>
            </div>
          </div>
        </section>

        <section className="we-card relative mt-10 rounded-3xl border-2 border-black bg-white p-8 shadow-[6px_6px_0_0_#000]">
          <h2 className="relative z-10 font-display mag-underline text-4xl tracking-tight">Safety notes</h2>
          <div aria-hidden className="pointer-events-none absolute -bottom-32 -right-60 z-0 hidden md:block">
            <Image
              src="/shapes/y2k/shape-90.png"
              alt=""
              width={200}
              height={200}
              className="y2k-pink opacity-28 -rotate-6"
            />
          </div>
          <div className="relative z-10 mt-3 grid gap-3 text-sm font-semibold text-zinc-800 md:grid-cols-2">
            <div className="rounded-2xl border-2 border-black bg-zinc-50 p-4">
              Deposits are tracked as liabilities; prizes are paid from surplus.
            </div>
            <div className="rounded-2xl border-2 border-black bg-zinc-50 p-4">
              Draw uses verifiable randomness; no block-timestamp RNG.
            </div>
            <div className="rounded-2xl border-2 border-black bg-zinc-50 p-4">
              You can withdraw anytime (no lockups).
            </div>
            <div className="rounded-2xl border-2 border-black bg-zinc-50 p-4">
              This is a demo; underlying yield sources carry real risk.
            </div>
          </div>
        </section>

        <footer className="mt-10 text-xs font-semibold text-zinc-700">
          Icons: Twemoji (CC-BY 4.0).
        </footer>
      </main>
    </div>
  );
}
