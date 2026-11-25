// The studios' log₂ brightness range (studio.ts): a byte v is 2^(LO + v / 255 · (HI − LO)). Here,
// apart, so a renderer can decode studios without loading three.js.
export const LO = -10;
export const HI = 7;
