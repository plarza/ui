// The studios that ship, each a CC0 panorama from Poly Haven turned to its best angle. Each URL is
// written out in full so bundlers can find the file (globs skip node_modules), and nothing is
// fetched until a logo uses that studio.
// `bun web/studios.ts` rebuilds Sources/AzaUI/Resources/Studios/*.avif from this list; AzaUI's ChromeStudio mirrors it.

export const studios = {
  monochrome: { source: 'monochrome_studio_04', angle: 180, url: new URL('../../Sources/AzaUI/Resources/Studios/monochrome.avif', import.meta.url) },
  broadway: { source: 'photo_studio_broadway_hall', angle: 0, url: new URL('../../Sources/AzaUI/Resources/Studios/broadway.avif', import.meta.url) },
  countryHall: { source: 'studio_country_hall', angle: 0, url: new URL('../../Sources/AzaUI/Resources/Studios/countryHall.avif', import.meta.url) },
  christmas: { source: 'christmas_photo_studio_07', angle: 180, url: new URL('../../Sources/AzaUI/Resources/Studios/christmas.avif', import.meta.url) },
  kominka: { source: 'studio_kominka_03', angle: 0, url: new URL('../../Sources/AzaUI/Resources/Studios/kominka.avif', import.meta.url) },
  white: { source: 'white_studio_03', angle: 0, url: new URL('../../Sources/AzaUI/Resources/Studios/white.avif', import.meta.url) },
  brown: { source: 'brown_photostudio_02', angle: 0, url: new URL('../../Sources/AzaUI/Resources/Studios/brown.avif', import.meta.url) },
  wizja: { source: 'studio_wizja_02', angle: 0, url: new URL('../../Sources/AzaUI/Resources/Studios/wizja.avif', import.meta.url) },
  london: { source: 'photo_studio_london_hall', angle: 180, url: new URL('../../Sources/AzaUI/Resources/Studios/london.avif', import.meta.url) },
  neon: { source: 'neon_photostudio', angle: 0, url: new URL('../../Sources/AzaUI/Resources/Studios/neon.avif', import.meta.url) },
  blocky: { source: 'blocky_photo_studio', angle: 0, url: new URL('../../Sources/AzaUI/Resources/Studios/blocky.avif', import.meta.url) },
};

export type StudioName = keyof typeof studios;
export const defaultStudio: StudioName = 'monochrome';
