import { Composition } from "remotion";
import { Preview, TOTAL } from "./Preview";

// App preview pro App Store: iPhone 6,9" = 886 × 1920, 30 fps, 15–30 s.
export const Root = () => (
  <Composition id="Preview" component={Preview} durationInFrames={TOTAL} fps={30} width={886} height={1920} />
);
