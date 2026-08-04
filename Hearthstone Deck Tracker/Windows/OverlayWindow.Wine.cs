using System;
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
		//   leaves the overlay behind on the old one. UpdatePosition() would not have
		//   helped even if the event arrived, because it returns early whenever the
		//   overlay's content is collapsed -- which is the whole time you are in the
		//   menus, i.e. exactly when you are likely to drag the game somewhere.
		//
		// Both are fixed the same way: stop trusting the notifications, poll, and
		// compare against where the overlay actually is rather than against the last
		// thing we were told. Native Windows is untouched -- the loop only starts when
		// running on Wine.

		private const int WinePollInterval = 500;

		private bool _runWinePolling;
		private bool _loggedWineMismatch;

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
			if(User32.GetHearthstoneWindow() == IntPtr.Zero)
				return;

			var hsRect = User32.GetHearthstoneRect(true);
			if(hsRect.Height <= 0)
				return;

			// Compare against where the overlay actually sits, not against the previous
			// reading of the game. Drift is the thing to correct, and it happens for
			// reasons a change-detector never sees -- most of all because
			// UpdatePosition() silently does nothing while the overlay's content is
			// collapsed, which is most of the time you are in the menus. Move the game
			// to another monitor there and the overlay is simply left behind.
			if((int)Left == hsRect.Left && (int)Top == hsRect.Top
				&& (int)Width == hsRect.Width && (int)Height == hsRect.Height)
			{
				_loggedWineMismatch = false;
			}
			else
			{
				if(!_loggedWineMismatch)
				{
					Log.Info($"Overlay at {(int)Left},{(int)Top} {(int)Width}x{(int)Height} does not match game at "
						+ $"{hsRect.Left},{hsRect.Top} {hsRect.Width}x{hsRect.Height}; repositioning");
					_loggedWineMismatch = true;
				}

				// SetRect unconditionally: it is what actually moves the window, and
				// unlike UpdatePosition it has no visibility guard. UpdatePosition on
				// top of it re-runs the layout, which is only worth doing, and only
				// works, when there is content to lay out.
				SetRect(hsRect.Top, hsRect.Left, hsRect.Width, hsRect.Height);
				if(IsContentVisible)
					UpdatePosition();
			}

			// Cheap enough to re-assert unconditionally: when the overlay is already on
			// top the X11 driver has nothing to change.
			User32.ForceTopmost(new WindowInteropHelper(this).Handle);
		}
	}
}
