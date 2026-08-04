using System;
using System.Drawing;
using System.Threading.Tasks;
using System.Windows.Interop;
using Hearthstone_Deck_Tracker.Utility;
using Hearthstone_Deck_Tracker.Utility.Logging;

namespace Hearthstone_Deck_Tracker.Windows
{
	public partial class OverlayWindow
	{
		// Under Wine the overlay's two mechanisms for staying glued to the game both
		// fail, in ways that look like separate bugs but share a cause: Win32 reports
		// success while the X11 window manager quietly does something else.
		//
		//   Stacking. Topmost is a Win32 concept. Wine translates WS_EX_TOPMOST into
		//   _NET_WM_STATE_ABOVE, but the window manager decides the final order, and
		//   Mutter raises the focused game above the overlay every time the game is
		//   clicked. SetTopmost() cannot notice, because it checks the style bit,
		//   which Wine still reports as set. The overlay ends up underneath the game
		//   and appears to have vanished.
		//
		//   Position. HookGameWindow() relies on SetWinEventHook with
		//   EVENT_OBJECT_LOCATIONCHANGE to learn that the game window moved. Wine
		//   raises that event for moves the application asks for, not for moves the
		//   window manager performs, so dragging Hearthstone to another monitor
		//   leaves the overlay behind on the old one.
		//
		// Both are fixed the same way: stop trusting the notifications and poll.
		// Native Windows is untouched -- the loop only starts when running on Wine.

		private const int WinePollInterval = 500;

		private bool _runWinePolling;
		private Rectangle _lastWineHsRect;

		private async void StartWinePolling()
		{
			if(!LinuxCompat.IsWine || _runWinePolling)
				return;
			_runWinePolling = true;
			Log.Info($"Running under Wine: polling game window position and stacking every {WinePollInterval}ms");
			while(_runWinePolling)
			{
				// Delay first: this is started from the constructor, ahead of
				// InitializeComponent, so there is nothing to poll yet.
				await Task.Delay(WinePollInterval);
				try
				{
					PollWineWindowState();
				}
				catch(Exception e)
				{
					Log.Error(e);
				}
			}
		}

		private void StopWinePolling() => _runWinePolling = false;

		private void PollWineWindowState()
		{
			if(!IsContentVisible)
				return;
			if(User32.GetHearthstoneWindow() == IntPtr.Zero)
				return;

			// Reposition only on an actual change. UpdatePosition() re-runs the whole
			// overlay layout, which is far too much to do twice a second for nothing.
			var hsRect = User32.GetHearthstoneRect(true);
			if(hsRect.Height > 0 && hsRect != _lastWineHsRect)
			{
				_lastWineHsRect = hsRect;
				UpdatePosition();
			}

			// Cheap enough to re-assert unconditionally: when the overlay is already on
			// top the X11 driver has nothing to change.
			User32.ForceTopmost(new WindowInteropHelper(this).Handle);
		}
	}
}
