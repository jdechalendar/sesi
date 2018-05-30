import pandas as pd
import matplotlib.pyplot as plt

def plotHeatmap(s, col, fillValue=None, ynTicks=10, xnTicks=8, cbar_label=None,
	scaling=1, vmin=None, vmax=None, fig=None, ax = None, with_cbar=True,
	cbar_nTicks=None, transpose=True):
    
    '''
        Plot a heatmap from time series data.
        Usage for dataframe df with timestamps in column "date_time" and data to
        plot in column "col" (grouped by frequency 'freq':
            
            df_hmap = df.groupby(pd.Grouper(key='date_time', freq=freq,
            	axis=1)).mean().fillna(method='pad',limit=fillna_limit)
            plotting.plotHeatmap(df_hmap, col)

        @param pandas.DataFrame s the data frame with the data to plot
        @param string col the column in df with the data to plot
        @param float fillValue the value to use to fill holes
        @param int nTicks the number of y ticks for the plot
        @param cbar_label string the label for the color bar
        @param float scaling a parameter to rescale the data
        @param float vmin min value for color bar
        @param float vmax max value for color bar

    '''

    if fillValue is None:
        fillValue = s[col].min()
    if cbar_label is None:
        cbar_label = col
    if cbar_label == "forceNone":
        cbar_label = None
    
    df_heatmap = pd.DataFrame(
        {"date": s.index.date, "time": s.index.time,
        "value_col": s[col].values*scaling}
    )

    if vmin is None:
        vmin = df_heatmap.value_col.min()
    if vmax is None:
        vmax = df_heatmap.value_col.max()

    df_heatmap = df_heatmap.pivot(index="date", columns='time',
    	values="value_col")
    df_heatmap.fillna(value=fillValue,inplace=True) # fill holes for plotting
    
    if fig is None:
        fig = plt.figure(figsize=(10,10))

    if ax is None:
        ax = plt.gca()
        
    if transpose:
        df_heatmap = df_heatmap.transpose()
        
    cax = ax.pcolor(df_heatmap, cmap='jet', vmin=vmin, vmax=vmax)
    
    ax.invert_yaxis()
    ynTicks = min(len(df_heatmap.index), ynTicks)
    xnTicks = min(len(df_heatmap.columns), xnTicks)
    ytickPos = range(0,len(df_heatmap.index),
    	int(len(df_heatmap.index)/ynTicks))
    xtickPos = range(0,len(df_heatmap.columns),
    	int(len(df_heatmap.columns)/xnTicks))

    if transpose:
        if with_cbar:
            if cbar_label is not None:
                cb = plt.colorbar(cax, label=cbar_label,
                	orientation='horizontal')
            else:
                cb = plt.colorbar(cax, orientation='horizontal')
            
        plt.xticks(xtickPos, [el.strftime('%m-%y') for el in
        	df_heatmap.columns[xtickPos]])
        plt.yticks(ytickPos, [el.hour for el in df_heatmap.index[ytickPos]]);
        plt.ylabel('hour')
        plt.xlabel('day')
        ax.xaxis.tick_top()
        ax.xaxis.set_label_position('top') 
    
    else:    
        if with_cbar:
            if cbar_label is not None:
                cb = plt.colorbar(cax, label=cbar_label)
            else:
                cb = plt.colorbar(cax)
            
        plt.yticks(ytickPos, df_heatmap.index[ytickPos])
        plt.xticks(xtickPos, [el.hour for el in df_heatmap.columns[xtickPos]]);
        plt.ylabel('day')
        plt.xlabel('hour')

    if with_cbar and cbar_nTicks is not None:
        from matplotlib import ticker
        tick_locator = ticker.MaxNLocator(nbins=cbar_nTicks, prune='both')
        cb.locator = tick_locator
        cb.update_ticks()
    if with_cbar:
        if transpose:
            cb.ax.set_xticklabels([l.get_text().strip('$') for l in
            	cb.ax.xaxis.get_ticklabels()])
        else:
            cb.ax.set_yticklabels([l.get_text().strip('$') for l in
            	cb.ax.yaxis.get_ticklabels()])


def reset_fonts(style="small", SMALL_SIZE=None, MEDIUM_SIZE= None,
	BIGGER_SIZE=None):
    
    if style == "big":
        SMALL_SIZE = 22
        MEDIUM_SIZE = 24
        BIGGER_SIZE = 26
    
    if SMALL_SIZE is None:
        SMALL_SIZE = 16
    
    if MEDIUM_SIZE is None:
        MEDIUM_SIZE = 18
    
    if BIGGER_SIZE is None:
        BIGGER_SIZE = 20
        
        
    plt.rc('font', size=SMALL_SIZE)          # controls default text sizes
    plt.rc('axes', titlesize=SMALL_SIZE)     # fontsize of the axes title
    plt.rc('axes', labelsize=MEDIUM_SIZE)    # fontsize of the x and y labels
    plt.rc('xtick', labelsize=SMALL_SIZE)    # fontsize of the tick labels
    plt.rc('ytick', labelsize=SMALL_SIZE)    # fontsize of the tick labels
    plt.rc('legend', fontsize=SMALL_SIZE)    # legend fontsize
    plt.rc('figure', titlesize=BIGGER_SIZE)  # fontsize of the figure title