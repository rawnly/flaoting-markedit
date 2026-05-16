import { EditorTheme } from '../types';

import XcodeLight from './xcode-light';
import XcodeDark from './xcode-dark';

const themes: { [key: string]: (() => EditorTheme) | undefined } = {
  'xcode-light': XcodeLight,
  'xcode-dark': XcodeDark,
};

export function loadTheme(name: string): EditorTheme {
  return (themes[name] ?? XcodeLight)();
}

export type { EditorTheme };
