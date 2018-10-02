/////////////////////////////////////////////////////////////////////////////
// Name:        src/osx/iphone/toolbar.mm
// Purpose:     wxToolBar
// Author:      Stefan Csomor
// Modified by:
// Created:     04/01/98
// Copyright:   (c) Stefan Csomor
// Licence:     wxWindows licence
/////////////////////////////////////////////////////////////////////////////

#include "wx/wxprec.h"

#if wxUSE_TOOLBAR

#include "wx/toolbar.h"

#ifndef WX_PRECOMP
#include "wx/wx.h"
#endif

#include "wx/app.h"
#include "wx/osx/private.h"
#include "wx/geometry.h"
#include "wx/sysopt.h"

#pragma mark -
#pragma mark Tool Implementation

wxBEGIN_EVENT_TABLE(wxToolBar, wxToolBarBase)
wxEND_EVENT_TABLE()

// ----------------------------------------------------------------------------
// definitions
// ----------------------------------------------------------------------------

class wxToolBarTool;

@interface wxUIToolBarButton : UIBarButtonItem
{
}

- (void) clickedAction: (id) sender;

@property (assign) wxToolBarTool *implementation;

@end

class wxToolBarTool : public wxToolBarToolBase
{
public:
    wxToolBarTool(
                  wxToolBar *tbar,
                  int id,
                  const wxString& label,
                  const wxBitmap& bmpNormal,
                  const wxBitmap& bmpDisabled,
                  wxItemKind kind,
                  wxObject *clientData,
                  const wxString& shortHelp,
                  const wxString& longHelp );

    wxToolBarTool(wxToolBar *tbar, wxControl *control, const wxString& label);

    virtual ~wxToolBarTool();

    void Action();

    wxUIToolBarButton* GetUIBarButtonItem() const {return m_toolbarItem;}
private:

    void Init();

    wxUIToolBarButton* m_toolbarItem;
    // position in its toolbar, -1 means not inserted
    CFIndex m_index;
};

@interface wxUIToolbar : UIToolbar<UIToolbarDelegate>
{
    NSMutableArray* mutableBarItems;
}

- (id)init;

- (void)insertTool:(UIBarButtonItem*) item atIndex:(size_t) pos;

- (void)removeTool:(size_t) pos;

- (UIBarPosition)positionForBar:(id <UIBarPositioning>)bar;

@end

// ----------------------------------------------------------------------------
// tool implementation
// ----------------------------------------------------------------------------

@implementation wxUIToolBarButton

- (void) clickedAction: (id) sender
{
    wxUnusedVar(sender);

    if ( self.implementation )
        self.implementation->Action();
}

@end

wxToolBarTool::wxToolBarTool(
    wxToolBar* tbar,
    int id,
    const wxString& label,
    const wxBitmap& bmpNormal,
    const wxBitmap& bmpDisabled,
    wxItemKind kind,
    wxObject* clientData,
    const wxString& shortHelp,
    const wxString& longHelp)
    : wxToolBarToolBase(
          tbar, id, label, bmpNormal, bmpDisabled, kind,
          clientData, shortHelp, longHelp)
{
    Init();

    wxUIToolBarButton* bui = [wxUIToolBarButton alloc];

    UIBarButtonItemStyle style = UIBarButtonItemStylePlain;

    if (id == wxID_OK)
        style = UIBarButtonItemStyleDone;

    if (id == wxID_SEPARATOR)
    {
        // at this moment isStretchable is always false, TODO: re-init if changed later
        bui = [bui initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:nil];
        bui.width = 25.0f;
    }
    else if (bmpNormal.IsOk())
    {
        bui = [bui initWithImage:bmpNormal.GetUIImage()
                           style:style
                          target:bui
                          action:@selector(clickedAction:)];
    }
    else
    {
        bui = [bui initWithTitle:wxCFStringRef(label).AsNSString()
                           style:style
                          target:bui
                          action:@selector(clickedAction:)];
    }

    m_toolbarItem = bui;
    m_toolbarItem.implementation = this;
}

wxToolBarTool::wxToolBarTool(wxToolBar *tbar, wxControl *control, const wxString& label)
: wxToolBarToolBase(tbar, control, label)
{
    Init();
    wxUIToolBarButton* bui = [wxUIToolBarButton alloc];

    [bui initWithCustomView:control->GetHandle() ];

    m_toolbarItem = bui;
    m_toolbarItem.implementation = this;
}

wxToolBarTool::~wxToolBarTool()
{
}

void wxToolBarTool::Init()
{
    m_toolbarItem = NULL;
    m_index = -1;
}

void wxToolBarTool::Action()
{
    wxToolBar *tbar = (wxToolBar*) GetToolBar();
    if (CanBeToggled())
    {
        bool    shouldToggle;

        shouldToggle = !IsToggled();
        tbar->ToggleTool( GetId(), shouldToggle );
    }

    tbar->OnLeftClick( GetId(), IsToggled() );
}

// ----------------------------------------------------------------------------
// toolbar implementation
// ----------------------------------------------------------------------------

@implementation wxUIToolbar

- (id)init
{
    if (!(self = [super init]))
        return nil;

    [self setDelegate:self];

    mutableBarItems = [NSMutableArray arrayWithCapacity:5];
    return self;
}

- (void)insertTool:(UIBarButtonItem*) item atIndex:(size_t) pos
{
    [mutableBarItems insertObject:item atIndex:pos];
    [super setItems:mutableBarItems];
}

- (void)removeTool:(size_t) pos
{
    [mutableBarItems removeObjectAtIndex:pos];
    [super setItems:mutableBarItems];
}

- (UIBarPosition)positionForBar:(id <UIBarPositioning>)bar
{
    UIBarPosition pos = UIBarPositionAny;

    wxToolBar* tb = dynamic_cast<wxToolBar*>(wxFindWindowFromWXWidget(self));
    if ( tb )
    {
        if (tb->HasFlag(wxTB_TOP))
            pos = UIBarPositionTopAttached;
        else if (tb->HasFlag(wxTB_BOTTOM))
            pos = UIBarPositionBottom;
    }

    return pos;
}

@end

wxToolBarToolBase *
wxToolBar::CreateTool(wxControl *control, const wxString& label)
{
    return new wxToolBarTool(this, control, label);
}

void wxToolBar::Init()
{
    m_maxWidth = -1;
    m_maxHeight = -1;

    m_macToolbar = NULL;
}

bool wxToolBar::Create(
                       wxWindow *parent,
                       wxWindowID id,
                       const wxPoint& pos,
                       const wxSize& size,
                       long style,
                       const wxString& name )
{
    DontCreatePeer();

    if ( !wxToolBarBase::Create( parent, id, pos, size, style, wxDefaultValidator, name ) )
        return false;

    FixupStyle();

    wxUIToolbar* toolbar = [[wxUIToolbar alloc] init];
    [toolbar sizeToFit];

    switch ( [[UIApplication sharedApplication] statusBarStyle] )
    {
        case UIStatusBarStyleDefault:
            toolbar.barStyle = UIBarStyleBlack;
            break;
        case UIStatusBarStyleLightContent:
            toolbar.barStyle = UIBarStyleBlack;
            toolbar.translucent = YES;
            break;
        default:
            toolbar.barStyle = UIBarStyleDefault;
            break;
    }
    m_macToolbar = toolbar;

    SetPeer(new wxWidgetIPhoneImpl( this, toolbar ));
    MacPostControlCreate(pos, size) ;
    return true;
}

wxToolBar::~wxToolBar()
{
    m_macToolbar = NULL;
}

bool wxToolBar::Realize()
{
    if ( !wxToolBarBase::Realize() )
        return false;


    return true;
}

void wxToolBar::DoLayout()
{
    // TODO port back osx_cocoa layout solution
}

void wxToolBar::DoSetSize(int x, int y, int width, int height, int sizeFlags)
{
    wxToolBarBase::DoSetSize(x, y, width, height, sizeFlags);

    DoLayout();
}

void wxToolBar::SetToolBitmapSize(const wxSize& size)
{
    m_defaultWidth = size.x;
    m_defaultHeight = size.y;
}

// The button size is bigger than the bitmap size
wxSize wxToolBar::GetToolSize() const
{
    return wxSize(m_defaultWidth, m_defaultHeight);
}

void wxToolBar::SetRows(int nRows)
{
    // avoid resizing the frame uselessly
    if ( nRows != m_maxRows )
        m_maxRows = nRows;
}

void wxToolBar::SetToolNormalBitmap( int id, const wxBitmap& bitmap )
{
    wxToolBarTool* tool = static_cast<wxToolBarTool*>(FindById(id));
    if ( tool )
    {
        wxCHECK_RET( tool->IsButton(), wxT("Can only set bitmap on button tools."));

        tool->SetNormalBitmap(bitmap);
    }
}

void wxToolBar::SetToolDisabledBitmap( int id, const wxBitmap& bitmap )
{
    wxToolBarTool* tool = static_cast<wxToolBarTool*>(FindById(id));
    if ( tool )
    {
        wxCHECK_RET( tool->IsButton(), wxT("Can only set bitmap on button tools."));

        tool->SetDisabledBitmap(bitmap);

        // TODO:  what to do for this one?
    }
}

wxToolBarToolBase *wxToolBar::FindToolForPosition(wxCoord x, wxCoord y) const
{
    return NULL;
}

void wxToolBar::DoEnableTool(wxToolBarToolBase *t, bool enable)
{
    /*
    if ( t != NULL )
        ((wxToolBarTool*)t)->DoEnable( enable );
     */
}

void wxToolBar::DoToggleTool(wxToolBarToolBase *t, bool toggle)
{
    /*
    wxToolBarTool *tool = (wxToolBarTool *)t;
    if ( ( tool != NULL ) && tool->IsButton() )
        tool->UpdateToggleImage( toggle );
     */
}

bool wxToolBar::DoInsertTool(size_t pos, wxToolBarToolBase *toolBase)
{
    wxToolBarTool *tool = static_cast< wxToolBarTool*>(toolBase );
    if (tool == NULL)
        return false;

    wxSize toolSize = GetToolSize();

    switch (tool->GetStyle())
    {
        case wxTOOL_STYLE_SEPARATOR:
            break;

        case wxTOOL_STYLE_BUTTON:
            break;

        case wxTOOL_STYLE_CONTROL:
            // right now there's nothing to do here
            break;

        default:
            break;
    }

    [(wxUIToolbar*)m_macToolbar insertTool:tool->GetUIBarButtonItem() atIndex:pos];
    InvalidateBestSize();

    return true;

}

void wxToolBar::DoSetToggle(wxToolBarToolBase *WXUNUSED(tool), bool WXUNUSED(toggle))
{
    wxFAIL_MSG( wxT("not implemented") );
}

bool wxToolBar::DoDeleteTool(size_t pos, wxToolBarToolBase *toolbase)
{
    wxToolBarTool* tool = static_cast< wxToolBarTool*>(toolbase );

    [(wxUIToolbar*)m_macToolbar removeTool:pos];

    return true;
}

void wxToolBar::SetWindowStyleFlag( long style )
{
    wxToolBarBase::SetWindowStyleFlag( style );

}

wxToolBarToolBase *wxToolBar::CreateTool(
                                         int id,
                                         const wxString& label,
                                         const wxBitmap& bmpNormal,
                                         const wxBitmap& bmpDisabled,
                                         wxItemKind kind,
                                         wxObject *clientData,
                                         const wxString& shortHelp,
                                         const wxString& longHelp )
{
    return new wxToolBarTool(this, id, label, bmpNormal, bmpDisabled, kind,
                             clientData, shortHelp, longHelp);
}

#endif // wxUSE_TOOLBAR
