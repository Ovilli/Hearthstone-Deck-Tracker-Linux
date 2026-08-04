using System;
using System.Runtime.InteropServices;

namespace Hearthstone_Deck_Tracker.Utility
{
	/// <summary>
	/// Detects whether HDT is running on top of Wine/Proton, which is how it is
	/// used on Linux: the tracker runs inside the same Wine prefix as
	/// Hearthstone so that HearthMirror can read the game's memory.
	/// A few Windows-only code paths have to be disabled in that setup.
	/// </summary>
	public static class LinuxCompat
	{
		[DllImport("kernel32.dll", CharSet = CharSet.Ansi, SetLastError = true)]
		private static extern IntPtr GetModuleHandleA(string moduleName);

		[DllImport("kernel32.dll", CharSet = CharSet.Ansi, SetLastError = true)]
		private static extern IntPtr GetProcAddress(IntPtr module, string procName);

		private static readonly Lazy<bool> LazyIsWine = new Lazy<bool>(() =>
		{
			try
			{
				// Wine exports wine_get_version from its ntdll. Nothing on a real
				// Windows install does, which makes this the standard check.
				var ntdll = GetModuleHandleA("ntdll.dll");
				return ntdll != IntPtr.Zero && GetProcAddress(ntdll, "wine_get_version") != IntPtr.Zero;
			}
			catch(Exception)
			{
				return false;
			}
		});

		/// <summary>True when running under Wine or Proton, i.e. on Linux.</summary>
		public static bool IsWine => LazyIsWine.Value;
	}
}
